require "test_helper"

class ExecutionTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:invoice_task)
    @agent = agents(:financial_agent)
    @execution = executions(:invoice_execution)
  end

  test "is valid with valid attributes" do
    assert @execution.valid?
  end

  test "requires task, agent, provider, ai_model, and valid status" do
    invalid = Execution.new(task: nil, agent: nil, provider: nil, ai_model: nil, status: "bogus")
    assert_not invalid.valid?
    assert_includes invalid.errors[:task], "must exist"
    assert_includes invalid.errors[:agent], "must exist"
    assert_includes invalid.errors[:provider], "can't be blank"
    assert_includes invalid.errors[:ai_model], "can't be blank"
    assert_includes invalid.errors[:status], "is not included in the list"
  end

  test "associations: belongs to task and agent, has many steps and audit events" do
    assert_equal @task, @execution.task
    assert_equal @agent, @execution.agent
    assert_equal @task.user, @execution.user
    assert_includes @execution.agent_steps, agent_steps(:step_one)
    assert_respond_to @execution, :audit_events
  end

  test "ordered agent_steps" do
    steps = @execution.agent_steps
    assert_equal 1, steps.first.position
    assert_equal 2, steps.second.position
  end
end
