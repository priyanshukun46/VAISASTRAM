require "test_helper"

class MockMcpProtocolClient
  attr_reader :server, :calls

  def initialize(server)
    @server = server
    @calls = []
  end

  def initialize_session!
    {
      protocol_version: "2024-11-05",
      server_info: { "name" => "MockEngine", "version" => "1.0.0" },
      capabilities: { "tools" => {} }
    }
  end

  def ping
    true
  end

  def list_tools
    [
      {
        "name" => "query_inventory",
        "description" => "Check warehouse inventory status",
        "inputSchema" => {
          "type" => "object",
          "properties" => { "sku" => { "type" => "string" } },
          "required" => ["sku"]
        }
      },
      {
        "name" => "adjust_inventory",
        "description" => "Adjust inventory counts (modifying action)",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "sku" => { "type" => "string" },
            "delta" => { "type" => "integer" }
          },
          "required" => ["sku", "delta"]
        }
      }
    ]
  end

  def call_tool(tool_name, arguments = {})
    @calls << { tool_name: tool_name, arguments: arguments }
    {
      "content" => [{ "type" => "text", "text" => "Inventory for #{arguments['sku'] || arguments[:sku]}: 42 units in stock" }],
      "text" => "Inventory for #{arguments['sku'] || arguments[:sku]}: 42 units in stock",
      "is_error" => false
    }
  end
end

class GovernedExecutionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @agent = agents(:financial_agent)

    @server = McpServer.create!(
      user: @user,
      name: "Inventory System",
      transport_type: "stdio",
      command: "node",
      arguments: ["server.js"],
      enabled: true,
      status: "connected"
    )

    @mock_client = MockMcpProtocolClient.new(@server)
    Mcp::ConnectionManager.mock_client_factory = ->(_srv) { @mock_client }
  end

  teardown do
    Mcp::ConnectionManager.mock_client_factory = nil
  end

  test "tool discovery imports tools with default deny policy and disabled state" do
    discovered = Mcp::ToolDiscovery.discover!(@server)
    assert_equal 2, discovered.size

    query_tool = @server.mcp_tools.find_by(external_tool_name: "query_inventory")
    assert_not_nil query_tool
    assert_equal "mcp.inventory_system.query_inventory", query_tool.namespaced_tool_key
    assert_not query_tool.enabled?, "Discovered tools must initially be disabled"
    assert_equal "deny", query_tool.policy_decision, "Discovered tools must default to deny policy"
    assert query_tool.schema_hash.present?

    # Verify audit event recorded
    last_event = AuditEvent.last
    assert_equal "mcp_tools_discovered", last_event.event_type
  end

  test "ruby policy engine strictly blocks tools set to deny or disabled" do
    Mcp::ToolDiscovery.discover!(@server)
    query_tool = @server.mcp_tools.find_by(external_tool_name: "query_inventory")

    # Evaluator should deny when disabled
    evaluator = Policies::Evaluator.new
    context = Policies::Context.new(
      action_key: query_tool.namespaced_tool_key,
      arguments: { "sku" => "SKU-99" },
      user: @user
    )
    decision = evaluator.evaluate(context)

    assert_equal "deny", decision.decision
    assert_match(/disabled|not permitted/i, decision.reason)
  end

  test "human approval binds to server config version and tool schema hash" do
    Mcp::ToolDiscovery.discover!(@server)
    adjust_tool = @server.mcp_tools.find_by(external_tool_name: "adjust_inventory")

    # Enable and configure tool to require approval
    adjust_tool.update!(enabled: true, policy_decision: "require_approval", risk_classification: "high")

    task = Task.create!(title: "Adjust stock", user: @user, agent: @agent, instruction: "Adjust stock for SKU-100", status: "running")
    execution = task.executions.create!(agent: @agent, status: "running", provider: "openai", ai_model: "gpt-4o")
    step = execution.agent_steps.create!(
      position: 1,
      action_key: adjust_tool.namespaced_tool_key,
      arguments: { "sku" => "SKU-100", "delta" => 5 },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @user)
    assert result.paused?, "Execution must pause when approval is required"

    approval = Approval.find_by(agent_step_id: step.id)
    assert_not_nil approval
    assert_equal "pending", approval.status
    assert_equal @server.id.to_s, approval.effective_arguments["_mcp_server_id"].to_s
    assert_equal @server.configuration_version.to_s, approval.effective_arguments["_mcp_config_version"].to_s
    assert_equal adjust_tool.schema_hash.to_s, approval.effective_arguments["_mcp_schema_hash"].to_s

    # Fingerprint validator passes initially
    validator = Approvals::FingerprintValidator.new(approval)
    assert validator.valid?, "Approval fingerprint must be valid initially"

    # Server configuration change invalidates prior approval
    @server.update!(arguments: ["server.js", "--verbose"])
    assert_not validator.valid?, "Configuration change must invalidate prior approval"
    assert_equal "invalidated", approval.reload.status
  end

  test "schema alteration invalidates prior approval" do
    Mcp::ToolDiscovery.discover!(@server)
    adjust_tool = @server.mcp_tools.find_by(external_tool_name: "adjust_inventory")
    adjust_tool.update!(enabled: true, policy_decision: "require_approval")

    task = Task.create!(title: "Adjust stock 2", user: @user, agent: @agent, instruction: "Adjust stock for SKU-200", status: "running")
    execution = task.executions.create!(agent: @agent, status: "running", provider: "openai", ai_model: "gpt-4o")
    step = execution.agent_steps.create!(
      position: 1,
      action_key: adjust_tool.namespaced_tool_key,
      arguments: { "sku" => "SKU-200", "delta" => 10 },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @user)
    approval = Approval.find_by(agent_step_id: step.id)
    validator = Approvals::FingerprintValidator.new(approval)
    assert validator.valid?, "Approval fingerprint must be valid initially"

    # Tool schema hash change invalidates approval
    adjust_tool.update!(input_schema: { "type" => "object", "properties" => { "sku" => { "type" => "string" }, "delta" => { "type" => "integer" }, "reason" => { "type" => "string" } } })
    assert_not validator.valid?, "Schema alteration must invalidate prior approval"
    assert_equal "invalidated", approval.reload.status
  end

  test "allowed and enabled tool executes successfully through Tools::Executor" do
    Mcp::ToolDiscovery.discover!(@server)
    query_tool = @server.mcp_tools.find_by(external_tool_name: "query_inventory")
    query_tool.update!(enabled: true, policy_decision: "allow", risk_classification: "low")

    task = Task.create!(title: "Query stock", user: @user, agent: @agent, instruction: "Query stock for SKU-ABC", status: "running")
    execution = task.executions.create!(agent: @agent, status: "running", provider: "openai", ai_model: "gpt-4o")
    step = execution.agent_steps.create!(
      position: 1,
      action_key: query_tool.namespaced_tool_key,
      arguments: { "sku" => "SKU-ABC" },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @user)
    assert result.success?, "Tool should execute cleanly when policy is allow"
    assert_equal 1, @mock_client.calls.size
    assert_equal "query_inventory", @mock_client.calls.first[:tool_name]
    assert_equal "SKU-ABC", @mock_client.calls.first[:arguments]["sku"]
  end
end
