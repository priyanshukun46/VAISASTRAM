require "test_helper"

class MockMcpTransport
  attr_reader :sent_requests, :server

  def initialize(server: nil)
    @server = server
    @sent_requests = []
    @responses = {}
  end

  def stub_response(method, response)
    @responses[method.to_s] = response
  end

  def send_request(payload, timeout: nil)
    @sent_requests << payload
    method = payload[:method] || payload["method"]

    if @responses.key?(method)
      res = @responses[method]
      res.is_a?(Proc) ? res.call(payload) : res
    else
      { "jsonrpc" => "2.0", "id" => payload[:id] || payload["id"], "result" => {} }
    end
  end
end

class ProtocolClientTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @server = McpServer.create!(
      user: @user,
      name: "Mock Service",
      transport_type: "stdio",
      command: "node",
      arguments: ["server.js"]
    )
    @transport = MockMcpTransport.new(server: @server)
    @client = Mcp::ProtocolClient.new(@transport, server: @server)
  end

  test "initializes session adhering to 2024-11-05 protocol specification" do
    @transport.stub_response("initialize", {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "protocolVersion" => "2024-11-05",
        "serverInfo" => { "name" => "MockEngine", "version" => "1.0.0" },
        "capabilities" => { "tools" => { "listChanged" => true } }
      }
    })

    result = @client.initialize_session!

    assert_equal "2024-11-05", result[:protocol_version]
    assert_equal "MockEngine", result[:server_info]["name"]
    assert_equal 2, @transport.sent_requests.size
    assert_equal "initialize", @transport.sent_requests[0][:method]
    assert_equal "notifications/initialized", @transport.sent_requests[1][:method]
  end

  test "lists tools and parses tool definitions" do
    @transport.stub_response("initialize", {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => { "protocolVersion" => "2024-11-05", "capabilities" => {} }
    })

    @transport.stub_response("tools/list", {
      "jsonrpc" => "2.0",
      "id" => 2,
      "result" => {
        "tools" => [
          {
            "name" => "query_sales",
            "description" => "Query quarterly sales numbers",
            "inputSchema" => { "type" => "object", "properties" => { "quarter" => { "type" => "string" } } }
          }
        ]
      }
    })

    tools = @client.list_tools
    assert_equal 1, tools.size
    assert_equal "query_sales", tools.first["name"]
  end

  test "calls tool and extracts text content on success" do
    @transport.stub_response("initialize", {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => { "protocolVersion" => "2024-11-05" }
    })

    @transport.stub_response("tools/call", {
      "jsonrpc" => "2.0",
      "id" => 2,
      "result" => {
        "content" => [
          { "type" => "text", "text" => "Q3 revenue was $4.2M" }
        ],
        "isError" => false
      }
    })

    res = @client.call_tool("query_sales", { quarter: "Q3" })
    assert_equal "Q3 revenue was $4.2M", res["text"]
    assert_equal false, res["is_error"]
  end

  test "raises ToolExecutionError when isError is true" do
    @transport.stub_response("initialize", {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => { "protocolVersion" => "2024-11-05" }
    })

    @transport.stub_response("tools/call", {
      "jsonrpc" => "2.0",
      "id" => 2,
      "result" => {
        "content" => [{ "type" => "text", "text" => "Database connection timeout" }],
        "isError" => true
      }
    })

    assert_raises(Mcp::ToolExecutionError) do
      @client.call_tool("query_sales", {})
    end
  end

  test "ping returns true on success and false on error" do
    @transport.stub_response("ping", { "jsonrpc" => "2.0", "id" => 1, "result" => {} })
    assert @client.ping

    @transport.stub_response("ping", { "jsonrpc" => "2.0", "id" => 2, "error" => { "code" => -32601, "message" => "Method not found" } })
    assert_not @client.ping
  end
end
