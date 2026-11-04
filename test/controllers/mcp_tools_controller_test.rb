require "test_helper"

class McpToolsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @operator = users(:one)
    @admin = users(:two)

    @server = McpServer.create!(
      user: @operator,
      name: "Operator Tool Server",
      transport_type: "stdio",
      command: "node",
      arguments: ["server.js"],
      enabled: true,
      status: "connected"
    )

    @tool = @server.mcp_tools.create!(
      external_tool_name: "query_database",
      description: "Query DB",
      input_schema: { "type" => "object" },
      enabled: false,
      policy_decision: "deny",
      risk_classification: "medium"
    )

    @admin_server = McpServer.create!(
      user: @admin,
      name: "Admin Tool Server",
      transport_type: "stdio",
      command: "python3",
      arguments: ["app.py"],
      enabled: true,
      status: "connected"
    )

    @admin_tool = @admin_server.mcp_tools.create!(
      external_tool_name: "admin_inspect",
      description: "Inspect system",
      input_schema: { "type" => "object" },
      enabled: false,
      policy_decision: "deny",
      risk_classification: "high"
    )
  end

  test "unauthenticated user cannot toggle or update tool" do
    patch toggle_mcp_server_mcp_tool_path(@server, @tool)
    assert_redirected_to new_user_session_path

    patch mcp_server_mcp_tool_path(@server, @tool), params: { mcp_tool: { policy_decision: "allow" } }
    assert_redirected_to new_user_session_path
  end

  test "operator can toggle tool enabled state" do
    sign_in @operator
    patch toggle_mcp_server_mcp_tool_path(@server, @tool)
    assert_redirected_to mcp_server_path(@server)
    assert @tool.reload.enabled?

    last_event = AuditEvent.last
    assert_equal "mcp_tool_enabled", last_event.event_type

    patch toggle_mcp_server_mcp_tool_path(@server, @tool)
    assert_redirected_to mcp_server_path(@server)
    assert_not @tool.reload.enabled?

    last_event = AuditEvent.last
    assert_equal "mcp_tool_disabled", last_event.event_type
  end

  test "operator can update tool policy decision and risk classification" do
    sign_in @operator
    patch mcp_server_mcp_tool_path(@server, @tool), params: {
      mcp_tool: {
        policy_decision: "require_approval",
        risk_classification: "high"
      }
    }
    assert_redirected_to mcp_server_path(@server)
    @tool.reload
    assert_equal "require_approval", @tool.policy_decision
    assert_equal "high", @tool.risk_classification

    last_event = AuditEvent.last
    assert_equal "policy_modified", last_event.event_type
  end

  test "operator cannot modify tool on another user's server" do
    sign_in @operator
    patch toggle_mcp_server_mcp_tool_path(@admin_server, @admin_tool)
    assert_redirected_to mcp_servers_path
    follow_redirect!
    assert_select "div", text: /not found/i
  end

  test "admin can modify tool on any server" do
    sign_in @admin
    patch mcp_server_mcp_tool_path(@server, @tool), params: {
      mcp_tool: {
        policy_decision: "allow",
        risk_classification: "low"
      }
    }
    assert_redirected_to mcp_server_path(@server)
    assert_equal "allow", @tool.reload.policy_decision
  end
end
