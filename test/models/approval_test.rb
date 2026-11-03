require "test_helper"

class ApprovalTest < ActiveSupport::TestCase
  setup do
    @approval = approvals(:pending_payment_approval)
    @step = agent_steps(:step_two)
    @reviewer = users(:two)
  end

  test "is valid with valid attributes" do
    assert @approval.valid?
  end

  test "requires agent_step, action_digest, and valid status" do
    invalid = Approval.new(agent_step: nil, action_digest: nil, status: "unknown")
    assert_not invalid.valid?
    assert_includes invalid.errors[:agent_step], "must exist"
    assert_includes invalid.errors[:action_digest], "can't be blank"
    assert_includes invalid.errors[:status], "is not included in the list"
  end

  test "generates canonical action digest" do
    action_key = "prepare_payment"
    arguments = { "invoice_id" => "INV-100", "amount" => 5000 }
    digest1 = Approval.generate_digest(action_key, arguments)
    digest2 = Approval.generate_digest(action_key, arguments)
    assert_equal digest1, digest2
    assert_equal 64, digest1.length # SHA256 hex string
  end

  test "lifecycle statuses and expiration logic" do
    @approval.status = "pending"
    @approval.expires_at = 1.hour.from_now
    assert @approval.pending?
    assert_not @approval.expired?

    # Time expiration
    @approval.expires_at = 1.hour.ago
    assert @approval.expired?
    assert_not @approval.pending?

    # Status explicitly expired
    @approval.status = "expired"
    assert @approval.expired?

    # Approved status
    @approval.status = "approved"
    assert @approval.approved?

    # Rejected status
    @approval.status = "rejected"
    assert @approval.rejected?

    # Phase 7 statuses
    @approval.status = "invalidated"
    assert @approval.invalidated?
    assert @approval.decided?

    @approval.status = "executed"
    assert @approval.executed?
    assert @approval.decided?

    @approval.status = "failed"
    assert @approval.failed?
    assert @approval.decided?
  end

  test "matches_fingerprint? validates against exact parameters" do
    step = agent_steps(:step_two)
    approval = Approval.create!(
      agent_step: step,
      user: users(:one),
      task: tasks(:invoice_task),
      execution: executions(:invoice_execution),
      tool_name: "prepare_payment",
      action_arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "pending",
      expires_at: 2.hours.from_now
    )

    assert approval.matches_fingerprint?

    # Tampering with arguments invalidates fingerprint match
    approval.action_arguments = { "invoice_id" => "INV-100", "amount" => 9999 }
    assert_not approval.matches_fingerprint?
  end

  test "associations: belongs to agent_step and optional reviewer, through execution and task" do
    assert_equal @step, @approval.agent_step
    assert_equal @reviewer, @approval.reviewer
    assert_equal @step.execution, @approval.execution
    assert_equal @step.execution.task, @approval.task
  end
end
