require "test_helper"

class McpSecurityTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  # =========================================================================
  # SSRF Guard Tests
  # =========================================================================

  test "SSRF Guard blocks IPv4 loopback (127.0.0.1 and localhost)" do
    check1 = Mcp::Security::SsrfGuard.check("http://127.0.0.1:8080/mcp")
    assert_not check1.safe?
    assert_match(/local|restricted|internal/, check1.reason)

    check2 = Mcp::Security::SsrfGuard.check("http://localhost:3000/mcp")
    assert_not check2.safe?
    assert_match(/local|restricted|internal/, check2.reason)
  end

  test "SSRF Guard blocks IPv6 loopback (::1)" do
    check = Mcp::Security::SsrfGuard.check("http://[::1]:8080/mcp")
    assert_not check.safe?
    assert_match(/local|restricted|internal/, check.reason)
  end

  test "SSRF Guard blocks RFC 1918 private IPv4 addresses" do
    private_ips = ["10.0.1.5", "172.16.4.1", "192.168.1.100"]
    private_ips.each do |ip|
      check = Mcp::Security::SsrfGuard.check("http://#{ip}/mcp")
      assert_not check.safe?, "Expected #{ip} to be blocked"
      assert_match(/restricted internal or private IP address/, check.reason)
    end
  end

  test "SSRF Guard blocks link-local / cloud metadata (169.254.169.254)" do
    check = Mcp::Security::SsrfGuard.check("http://169.254.169.254/latest/meta-data/")
    assert_not check.safe?
    assert_match(/restricted internal or private IP address/, check.reason)
  end

  test "SSRF Guard allows local connections only when explicitly permitted by administrator" do
    check = Mcp::Security::SsrfGuard.check("http://127.0.0.1:8080/mcp", allow_local: true)
    assert check.safe?
    assert_equal "Local connections explicitly permitted by administrator", check.reason
  end

  test "SSRF Guard permits public HTTPS domain" do
    check = Mcp::Security::SsrfGuard.check("https://api.example.com/mcp")
    assert check.safe?
  end

  # =========================================================================
  # Command Injection & Executable Allowlist Tests
  # =========================================================================

  test "McpServer rejects dangerous shell commands" do
    dangerous_commands = %w[bash sh zsh sudo rm curl wget nc]
    dangerous_commands.each do |cmd|
      server = McpServer.new(
        user: @user,
        name: "Malicious #{cmd}",
        transport_type: "stdio",
        command: cmd,
        arguments: ["-c", "id"]
      )
      assert_not server.valid?, "Expected command '#{cmd}' to be rejected"
      assert server.errors[:command].any? { |e| e.include?("prohibited") || e.include?("allowlist") }
    end
  end

  test "McpServer rejects path traversal in command" do
    server = McpServer.new(
      user: @user,
      name: "Path Traversal Server",
      transport_type: "stdio",
      command: "../../bin/evil_tool",
      arguments: []
    )
    assert_not server.valid?
    assert server.errors[:command].any? { |e| e.include?("traversal") }
  end

  test "McpServer permits allowed safe executables" do
    allowed = %w[npx node python python3 ruby uvx deno bun wordcraft]
    allowed.each do |cmd|
      server = McpServer.new(
        user: @user,
        name: "Safe #{cmd} Server",
        transport_type: "stdio",
        command: cmd,
        arguments: ["--version"]
      )
      assert server.valid?, "Expected '#{cmd}' to be valid, got errors: #{server.errors.full_messages}"
    end
  end

  test "McpServer rejects non-array arguments" do
    server = McpServer.new(
      user: @user,
      name: "Invalid Args Server",
      transport_type: "stdio",
      command: "node",
      arguments: "index.js --foo=bar" # String instead of Array
    )
    assert_not server.valid?
    assert_includes server.errors[:arguments], "must be an array of argument strings"
  end

  # =========================================================================
  # Active Record Encryption of Secrets
  # =========================================================================

  test "encrypts environment_variables and authentication_configuration in database" do
    server = McpServer.create!(
      user: @user,
      name: "Secret Bearing Server",
      transport_type: "streamable_http",
      endpoint_url: "https://api.example.com/mcp",
      environment_variables: "API_SECRET=super-secret-token-12345",
      authentication_configuration: "{\"bearer_token\":\"bearer-auth-abcde\"}"
    )

    # In Ruby model, attributes and helper methods decrypt values
    assert_equal "super-secret-token-12345", server.env_hash["API_SECRET"]
    assert_equal "Bearer bearer-auth-abcde", server.auth_headers["Authorization"]

    # In raw SQL, the values are encrypted ciphertext, NOT plaintext
    raw_row = ActiveRecord::Base.connection.select_one("SELECT environment_variables, authentication_configuration FROM mcp_servers WHERE id = #{server.id}")
    assert_not_includes raw_row["environment_variables"], "super-secret-token-12345"
    assert_not_includes raw_row["authentication_configuration"], "bearer-auth-abcde"
  end
end
