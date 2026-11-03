require "test_helper"

class AgentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @agent = agents(:financial_agent)
  end

  test "is valid with valid attributes" do
    assert @agent.valid?
  end

  test "requires user, name, and valid status" do
    invalid_agent = Agent.new(name: nil, user: nil, status: "unknown")
    assert_not invalid_agent.valid?
    assert_includes invalid_agent.errors[:name], "can't be blank"
    assert_includes invalid_agent.errors[:user], "must exist"
    assert_includes invalid_agent.errors[:status], "is not included in the list"
  end

  test "associations: belongs to user, has many tasks and executions" do
    assert_equal @user, @agent.user
    assert_respond_to @agent, :tasks
    assert_respond_to @agent, :executions
  end

  test "status predicates work correctly" do
    @agent.status = "active"
    assert @agent.active?
    assert_not @agent.paused?

    @agent.status = "paused"
    assert @agent.paused?

    @agent.status = "archived"
    assert @agent.archived?
  end
end
