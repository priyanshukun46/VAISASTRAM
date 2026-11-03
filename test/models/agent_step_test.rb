require "test_helper"

class AgentStepTest < ActiveSupport::TestCase
  setup do
    @execution = executions(:invoice_execution)
    @step = agent_steps(:step_one)
  end

  test "is valid with valid attributes" do
    assert @step.valid?
  end

  test "requires execution, position, action_key, valid risk_level and status" do
    invalid = AgentStep.new(execution: nil, position: nil, action_key: nil, risk_level: "extreme", status: "weird")
    assert_not invalid.valid?
    assert_includes invalid.errors[:execution], "must exist"
    assert_includes invalid.errors[:position], "can't be blank"
    assert_includes invalid.errors[:action_key], "can't be blank"
    assert_includes invalid.errors[:risk_level], "is not included in the list"
    assert_includes invalid.errors[:status], "is not included in the list"
  end

  test "enforces unique position per execution" do
    duplicate_position = AgentStep.new(
      execution: @execution,
      position: @step.position, # position 1 already exists
      action_key: "verify_invoice",
      risk_level: "low",
      status: "pending"
    )
    assert_not duplicate_position.valid?
    assert_includes duplicate_position.errors[:position], "has already been taken"
  end

  test "allows same position across different executions" do
    other_task = Task.create!(user: users(:two), agent: agents(:admin_agent), title: "Task 2", instruction: "Do something")
    other_execution = Execution.create!(task: other_task, agent: agents(:admin_agent), provider: "gemini", ai_model: "gemini-2.5-pro", status: "pending")

    step_in_other_execution = AgentStep.new(
      execution: other_execution,
      position: @step.position, # position 1 in another execution
      action_key: "lookup_invoice",
      risk_level: "low",
      status: "pending"
    )
    assert step_in_other_execution.valid?
  end

  test "validates policy decision when present" do
    @step.policy_decision = "invalid_decision"
    assert_not @step.valid?
    assert_includes @step.errors[:policy_decision], "is not included in the list"

    @step.policy_decision = "allow"
    assert @step.valid?

    @step.policy_decision = nil
    assert @step.valid?
  end

  test "associations: belongs to execution, has many approvals and audit events" do
    assert_equal @execution, @step.execution
    assert_respond_to @step, :approvals
    assert_respond_to @step, :audit_events
  end
end
