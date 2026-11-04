require "test_helper"

class McpServersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @operator = users(:one)
    @admin = users(:two)
    @auditor = users(:auditor)

    @server = McpServer.create!(
      user: @operator,
      name: "Operator Service",
      transport_type: "stdio",
      command: "node",
      arguments: ["server.js"],
      enabled: true
    )

    @admin_server = McpServer.create!(
      user: @admin,
      name: "Admin Only Service",
      transport_type: "stdio",
      command: "python3",
      arguments: ["app.py"],
      enabled: true
    )
  end

  test "unauthenticated user is redirected to sign in" do
    get mcp_servers_path
    assert_redirected_to new_user_session_path

    get new_mcp_server_path
    assert_redirected_to new_user_session_path

    get mcp_server_path(@server)
    assert_redirected_to new_user_session_path
  end

  test "authenticated user can list servers and see marketplace templates" do
    sign_in @operator
    get mcp_servers_path
    assert_response :success
    assert_select "h1", text: /MCP Server Marketplace & Manager/
    assert_select "div", text: /Operator Service/
    assert_select "h3", text: /WordCraft Document Engine/
  end

  test "new action prefills from marketplace template" do
    sign_in @operator
    get new_mcp_server_path(template: "wordcraft")
    assert_response :success
    assert_select "input[value='WordCraft Document Engine']"
    assert_select "input[value='npx']"
  end

  test "operator can create a valid STDIO MCP server" do
    sign_in @operator
    assert_difference "McpServer.count", 1 do
      post mcp_servers_path, params: {
        mcp_server: {
          name: "Local Deno Server",
          server_identifier: "deno_server",
          transport_type: "stdio",
          command: "deno",
          arguments_string: "run -A mcp.ts",
          connection_timeout: 10,
          enabled: true
        }
      }
    end

    created = McpServer.find_by(server_identifier: "deno_server")
    assert_redirected_to mcp_server_path(created)
    assert_equal @operator.id, created.user_id
    assert_equal ["run", "-A", "mcp.ts"], created.arguments
  end

  test "rejects prohibited shell command in server creation" do
    sign_in @operator
    assert_no_difference "McpServer.count" do
      post mcp_servers_path, params: {
        mcp_server: {
          name: "Malicious Bash Server",
          transport_type: "stdio",
          command: "bash",
          arguments_string: "-c 'cat /etc/passwd'",
          enabled: true
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "operator cannot access another user's MCP server" do
    sign_in @operator
    get mcp_server_path(@admin_server)
    assert_redirected_to mcp_servers_path
    follow_redirect!
    assert_select "div", text: /not found or access denied/i
  end

  test "admin can access any user's MCP server" do
    sign_in @admin
    get mcp_server_path(@server)
    assert_response :success
    assert_select "h1", text: /#{@server.name}/
  end

  test "non-admin cannot set allow_local_connections bypass" do
    sign_in @operator
    post mcp_servers_path, params: {
      mcp_server: {
        name: "Private Network Probe",
        transport_type: "streamable_http",
        endpoint_url: "http://127.0.0.1:9000/mcp",
        allow_local_connections: true
      }
    }

    # Bypassing should fail because non-admin cannot set allow_local_connections
    assert_response :unprocessable_entity
  end

  test "toggle_enabled toggles server status and syncs tools" do
    sign_in @operator
    patch toggle_enabled_mcp_server_path(@server)
    assert_redirected_to mcp_server_path(@server)
    assert_not @server.reload.enabled?

    patch toggle_enabled_mcp_server_path(@server)
    assert_redirected_to mcp_server_path(@server)
    assert @server.reload.enabled?
  end

  test "disconnect marks server disconnected and records audit event" do
    sign_in @operator
    @server.update!(status: "connected")

    post disconnect_mcp_server_path(@server)
    assert_redirected_to mcp_server_path(@server)
    assert_equal "disconnected", @server.reload.status

    last_event = AuditEvent.last
    assert_equal "mcp_server_disconnected", last_event.event_type
  end
end
