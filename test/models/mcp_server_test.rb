require "test_helper"

class McpServerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "validates presence of name and transport_type" do
    server = McpServer.new(transport_type: nil)
    assert_not server.valid?
    assert_includes server.errors[:name], "can't be blank"
    assert_includes server.errors[:transport_type], "can't be blank"
  end

  test "auto-generates server_identifier slug from name" do
    server = McpServer.create!(
      user: @user,
      name: "Acme Analytics Service",
      transport_type: "stdio",
      command: "npx",
      arguments: ["-y", "acme-analytics"]
    )
    assert_equal "acme_analytics_service", server.server_identifier
  end

  test "enforces uniqueness of server_identifier" do
    McpServer.create!(
      user: @user,
      name: "Server Alpha",
      server_identifier: "alpha_server",
      transport_type: "stdio",
      command: "node",
      arguments: ["server.js"]
    )

    duplicate = McpServer.new(
      user: @user,
      name: "Server Alpha Duplicate",
      server_identifier: "alpha_server",
      transport_type: "stdio",
      command: "node",
      arguments: ["server.js"]
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:server_identifier], "has already been taken"
  end

  test "rejects prohibited shell and administrative commands (command injection defense)" do
    %w[bash sh zsh sudo rm curl wget powershell cmd.exe].each do |bad_cmd|
      server = McpServer.new(
        user: @user,
        name: "Malicious Server",
        transport_type: "stdio",
        command: bad_cmd,
        arguments: ["-c", "whoami"]
      )
      assert_not server.valid?, "Expected #{bad_cmd} to be rejected"
      assert server.errors[:command].any? { |e| e.include?("prohibited") || e.include?("allowlist") }
    end
  end

  test "rejects path traversal in command" do
    server = McpServer.new(
      user: @user,
      name: "Traversal Server",
      transport_type: "stdio",
      command: "../../../bin/node",
      arguments: []
    )
    assert_not server.valid?
    assert server.errors[:command].any? { |e| e.include?("path traversal") }
  end

  test "rejects unallowlisted executables" do
    server = McpServer.new(
      user: @user,
      name: "Custom Binary Server",
      transport_type: "stdio",
      command: "arbitrary_custom_binary",
      arguments: []
    )
    assert_not server.valid?
    assert server.errors[:command].any? { |e| e.include?("allowlist") }
  end

  test "validates streamable HTTP URL and rejects SSRF loopback targets without admin bypass" do
    server = McpServer.new(
      user: @user,
      name: "Localhost HTTP Server",
      transport_type: "streamable_http",
      endpoint_url: "http://127.0.0.1:8080/mcp",
      allow_local_connections: false
    )
    assert_not server.valid?
    assert server.errors[:endpoint_url].any? { |e| e.include?("SSRF") || e.include?("HTTPS") }
  end

  test "permits streamable HTTP with valid HTTPS remote URL" do
    server = McpServer.new(
      user: @user,
      name: "Remote MCP Service",
      transport_type: "streamable_http",
      endpoint_url: "https://api.example.com/mcp"
    )
    assert server.valid?, server.errors.full_messages.join(", ")
  end

  test "Active Record Encryption encrypts environment variables and credentials at rest" do
    server = McpServer.create!(
      user: @user,
      name: "Secure Server",
      transport_type: "stdio",
      command: "node",
      arguments: ["index.js"],
      environment_variables: "SECRET_KEY=super_secret_value_12345",
      authentication_configuration: "{\"bearer_token\": \"top_secret_token_999\"}"
    )

    # In Ruby, decrypted values are accessible
    assert_equal "super_secret_value_12345", server.env_hash["SECRET_KEY"]
    assert_equal "Bearer top_secret_token_999", server.auth_headers["Authorization"]

    # In raw SQL, the stored column must NOT be plaintext
    raw_row = ActiveRecord::Base.connection.select_one("SELECT environment_variables, authentication_configuration FROM mcp_servers WHERE id = #{server.id}")
    assert_not_equal "SECRET_KEY=super_secret_value_12345", raw_row["environment_variables"]
    assert_not_includes raw_row["environment_variables"], "super_secret_value_12345"
  end

  test "increments configuration_version when connection parameters change" do
    server = McpServer.create!(
      user: @user,
      name: "Versioned Server",
      transport_type: "stdio",
      command: "node",
      arguments: ["v1.js"]
    )
    assert_equal 1, server.configuration_version

    server.update!(arguments: ["v2.js"])
    assert_equal 2, server.configuration_version
  end
end
