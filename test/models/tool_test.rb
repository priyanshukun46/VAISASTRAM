require "test_helper"

class ToolTest < ActiveSupport::TestCase
  setup do
    @tool = tools(:lookup_tool)
  end

  test "is valid with valid attributes" do
    assert @tool.valid?
  end

  test "requires key, name, and valid risk_level" do
    invalid = Tool.new(key: nil, name: nil, risk_level: "disaster")
    assert_not invalid.valid?
    assert_includes invalid.errors[:key], "can't be blank"
    assert_includes invalid.errors[:name], "can't be blank"
    assert_includes invalid.errors[:risk_level], "is not included in the list"
  end

  test "enforces unique key" do
    duplicate = Tool.new(
      key: @tool.key,
      name: "Duplicate tool",
      risk_level: "low",
      enabled: true
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "validates key format allows only lowercase letters, numbers, underscores, and dots" do
    invalid_format = Tool.new(key: "Bad Key!", name: "Invalid Tool", risk_level: "low")
    assert_not invalid_format.valid?
    assert_includes invalid_format.errors[:key], "must contain only lowercase letters, numbers, underscores, and dots"

    valid_format = Tool.new(key: "valid_action_123", name: "Valid Tool", risk_level: "low", enabled: true)
    assert valid_format.valid?

    namespaced_mcp_format = Tool.new(key: "mcp.wordcraft.inspect_document", name: "MCP Tool", risk_level: "low", enabled: true)
    assert namespaced_mcp_format.valid?
  end

  test "scopes: enabled and by_risk" do
    assert_includes Tool.enabled, @tool
    assert_includes Tool.by_risk("low"), @tool
    assert_not_includes Tool.by_risk("high"), @tool
  end
end
