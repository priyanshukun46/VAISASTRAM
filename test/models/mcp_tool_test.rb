require "test_helper"

class McpToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @server = McpServer.create!(
      user: @user,
      name: "Acme Data Service",
      transport_type: "stdio",
      command: "npx",
      arguments: ["-y", "acme-service"]
    )
  end

  test "generates namespaced tool key on validation" do
    tool = McpTool.new(
      mcp_server: @server,
      external_tool_name: "query_database",
      description: "Run read-only query on customer database",
      input_schema: { "type" => "object", "properties" => { "query" => { "type" => "string" } } }
    )
    assert tool.valid?
    assert_equal "mcp.acme_data_service.query_database", tool.namespaced_tool_key
    assert tool.schema_hash.present?
  end

  test "defaults to disabled and deny policy for safety" do
    tool = McpTool.create!(
      mcp_server: @server,
      external_tool_name: "list_tables",
      description: "List available database tables",
      input_schema: { "type" => "object" }
    )
    assert_not tool.enabled?
    assert_equal "deny", tool.policy_decision
  end

  test "computes reproducible canonical schema hash regardless of key ordering" do
    schema1 = { "b" => 2, "a" => 1, "c" => { "y" => 20, "x" => 10 } }
    schema2 = { "a" => 1, "c" => { "x" => 10, "y" => 20 }, "b" => 2 }

    hash1 = McpTool.compute_schema_hash(schema1)
    hash2 = McpTool.compute_schema_hash(schema2)

    assert_equal hash1, hash2
  end

  test "detects schema change and updates schema_hash" do
    tool = McpTool.create!(
      mcp_server: @server,
      external_tool_name: "fetch_record",
      input_schema: { "type" => "object", "properties" => { "id" => { "type" => "integer" } } }
    )
    original_hash = tool.schema_hash

    tool.update!(input_schema: { "type" => "object", "properties" => { "id" => { "type" => "string" } } })
    assert_not_equal original_hash, tool.schema_hash
  end

  test "rejects tool names colliding with built-in tools" do
    tool = McpTool.new(
      mcp_server: @server,
      external_tool_name: "verify_invoice",
      input_schema: {}
    )
    assert_not tool.valid?
    assert_includes tool.errors[:external_tool_name], "'verify_invoice' collides with a core built-in VAISASTRAM tool and cannot be overridden"
  end

  test "synchronizes with Tool registry on save and removes on destroy" do
    @server.update!(status: "connected", enabled: true)

    tool = McpTool.create!(
      mcp_server: @server,
      external_tool_name: "search_docs",
      description: "Search corporate knowledge base",
      input_schema: { "type" => "object" },
      enabled: true,
      policy_decision: "allow"
    )

    registry_tool = Tool.find_by(key: "mcp.acme_data_service.search_docs")
    assert_not_nil registry_tool
    assert_equal "Acme Data Service — Search docs", registry_tool.name
    assert registry_tool.enabled?

    tool.destroy
    assert_nil Tool.find_by(key: "mcp.acme_data_service.search_docs")
  end
end
