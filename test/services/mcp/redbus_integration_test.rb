require "test_helper"

class RedbusIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @agent = agents(:financial_agent)

    @server = McpServer.create!(
      user: @user,
      name: "RedBus Ticket Service",
      server_identifier: "redbus",
      transport_type: "stdio",
      command: "ruby",
      arguments: ["bin/mcp-redbus-server"],
      enabled: true
    )
  end

  teardown do
    Mcp::ConnectionManager.disconnect(@server) rescue nil
  end

  test "initializes handshake and discovers RedBus tools" do
    health = Mcp::Client.connect(@server)
    assert health[:success], "Failed to connect: #{health[:error]}"
    assert_equal "connected", @server.reload.status

    tools = Mcp::Client.discover_tools(@server)
    assert_equal 4, tools.size

    tool_names = tools.map(&:external_tool_name)
    assert_includes tool_names, "search_bus_routes"
    assert_includes tool_names, "get_ticket_price"
    assert_includes tool_names, "check_seat_layout"
    assert_includes tool_names, "estimate_route_fare"

    price_tool = @server.mcp_tools.find_by(external_tool_name: "get_ticket_price")
    assert_equal "mcp.redbus.get_ticket_price", price_tool.namespaced_tool_key
    assert_not price_tool.enabled?, "Discovered tools must initially be disabled"
    assert_equal "deny", price_tool.policy_decision
  end

  test "executes get_ticket_price and returns comprehensive fare breakdown" do
    Mcp::Client.connect(@server)
    Mcp::Client.discover_tools(@server)

    price_tool = @server.mcp_tools.find_by(external_tool_name: "get_ticket_price")
    price_tool.update!(enabled: true, policy_decision: "allow", risk_classification: "low")

    res = Mcp::Client.call_tool(@server, "get_ticket_price", {
      "source" => "Bangalore",
      "destination" => "Hyderabad",
      "seat_category" => "single_sleeper"
    })

    assert_not res["is_error"]
    assert_match(/REDBUS FARE BREAKDOWN/i, res["text"])
    assert_match(/Base Ticket Fare/i, res["text"])
    assert_match(/TOTAL TICKET PRICE/i, res["text"])
    assert_equal 1388, res.dig("metadata", "total_fare_inr")
  end

  test "executes search_bus_routes and lists multiple bus operators and fares" do
    Mcp::Client.connect(@server)
    Mcp::Client.discover_tools(@server)

    search_tool = @server.mcp_tools.find_by(external_tool_name: "search_bus_routes")
    search_tool.update!(enabled: true, policy_decision: "allow", risk_classification: "low")

    res = Mcp::Client.call_tool(@server, "search_bus_routes", {
      "source" => "Delhi",
      "destination" => "Jaipur",
      "ac_only" => true
    })

    assert_not res["is_error"]
    assert_match(/REDBUS TICKET SEARCH: Delhi -> Jaipur/i, res["text"])
    assert_match(/Ticket Price: ₹/i, res["text"])
    assert res.dig("metadata", "total_buses") > 0
  end

  test "dispatches through Tools::Executor with Ruby policy governance" do
    Mcp::Client.connect(@server)
    Mcp::Client.discover_tools(@server)

    price_tool = @server.mcp_tools.find_by(external_tool_name: "get_ticket_price")
    price_tool.update!(enabled: true, policy_decision: "allow", risk_classification: "low")

    task = Task.create!(title: "Check RedBus Ticket Price", user: @user, agent: @agent, instruction: "Find ticket price from Mumbai to Goa", status: "running")
    execution = task.executions.create!(agent: @agent, status: "running", provider: "openai", ai_model: "gpt-4o")
    step = execution.agent_steps.create!(
      position: 1,
      action_key: price_tool.namespaced_tool_key,
      arguments: { "source" => "Mumbai", "destination" => "Goa", "seat_category" => "semi_sleeper" },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @user)
    assert result.success?, "Tool should execute cleanly under allow policy"
    assert_match(/TOTAL TICKET PRICE/i, result.result["text"])
  end
end
