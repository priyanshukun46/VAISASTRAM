require "test_helper"
require "ostruct"

class ApprovalsServiceTest < ActiveSupport::TestCase
  setup do
    @admin = users(:two)
    @operator = users(:one)
    @auditor = users(:auditor)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)
    @step = @execution.agent_steps.create!(
      position: 100,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "pending",
      risk_level: "high"
    )
    @service = Approvals::Service.new
  end

  # --- LIFECYCLE TESTS ---

  test "Test 1: REQUIRE_APPROVAL creates a pending approval record" do
    decision = Policies::Decision.require_approval(
      policy_id: "payment_approval_threshold",
      reason: "Payment of ₹5,000 requires human review",
      action_fingerprint: "sample_fp_123"
    )

    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      decision: decision
    )

    assert approval.persisted?
    assert_equal "pending", approval.status
    assert_equal "prepare_payment", approval.tool_name
    assert_equal 5000, approval.action_arguments["amount"]
    assert approval.expires_at > Time.current
    assert_not_nil approval.action_fingerprint
  end

  test "Test 3 & 6: Authorized reviewer can approve and resumes execution" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      decision: Policies::Decision.require_approval(policy_id: "payment_rule", reason: "Requires approval")
    )

    # Admin is authorized to approve
    decision = @service.approve(approval_id: approval.id, reviewer: @admin)

    assert decision.success?
    assert decision.approved?
    approval.reload
    assert_equal "executed", approval.status
    assert_equal @admin, approval.reviewer
    assert_not_nil approval.reviewed_at

    # Check that tool was executed safely and step was completed
    @step.reload
    assert_equal "completed", @step.status
    assert_equal "voucher_prepared", @step.result["status"]
  end

  test "Test 4 & 5 & 7: Authorized reviewer can reject with recorded reason and tool never executes" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      decision: Policies::Decision.require_approval(policy_id: "payment_rule", reason: "Requires approval")
    )

    decision = @service.reject(
      approval_id: approval.id,
      reviewer: @admin,
      reason: "Suspicious vendor discrepancy detected"
    )

    assert decision.rejected?
    approval.reload
    assert_equal "rejected", approval.status
    assert_equal "Suspicious vendor discrepancy detected", approval.rejection_reason
    assert_equal @admin, approval.reviewer

    # Check step is rejected and tool never ran
    @step.reload
    assert_equal "rejected", @step.status
    assert_includes @step.result["reason"], "Suspicious vendor discrepancy detected"
  end

  test "Test 8 & 23: Expired approval cannot be approved or executed and cannot be revived" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      expires_in: 1.second
    )

    # Fast forward past expiration
    approval.update_columns(expires_at: 10.minutes.ago)

    assert_raises(Approvals::ExpiredError) do
      @service.approve(approval_id: approval.id, reviewer: @admin)
    end

    approval.reload
    assert_equal "expired", approval.status

    # Cannot revive
    assert_raises(Approvals::DuplicateDecisionError) do
      @service.approve(approval_id: approval.id, reviewer: @admin)
    end
  end

  # --- SECURITY TESTS ---

  test "Test 9: Unauthenticated or nil reviewer cannot approve" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    assert_raises(Approvals::UnauthorizedReviewerError) do
      @service.approve(approval_id: approval.id, reviewer: nil)
    end
  end

  test "Test 10: Unauthorized user (e.g. auditor or task creator operator) cannot approve" do
    approval = @service.create_request(
      user: @operator, # @task belongs to @operator
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    # Auditor cannot approve (read-only role)
    assert_raises(Approvals::UnauthorizedReviewerError) do
      @service.approve(approval_id: approval.id, reviewer: @auditor)
    end

    # Operator who created the task cannot approve (segregation of duties)
    assert_raises(Approvals::UnauthorizedReviewerError) do
      @service.approve(approval_id: approval.id, reviewer: @operator)
    end
  end

  test "Test 12: AI agents cannot act as human reviewers" do
    ai_mock = OpenStruct.new(id: 999, agent?: true, role: "agent")

    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    assert_raises(Approvals::UnauthorizedReviewerError) do
      @service.approve(approval_id: approval.id, reviewer: ai_mock)
    end
  end

  test "Test 14: Modified arguments invalidate approval and block execution" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    # Tamper with stored arguments in DB
    approval.update_columns(action_arguments: { "invoice_id" => "INV-100", "amount" => 8000 })

    assert_raises(Approvals::FingerprintMismatchError) do
      @service.approve(approval_id: approval.id, reviewer: @admin)
    end

    approval.reload
    assert_equal "invalidated", approval.status
    @step.reload
    assert_equal "blocked", @step.status
  end

  test "Test 15: Modified tool name invalidates approval" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    approval.update_columns(tool_name: "delete_financial_record")

    assert_raises(Approvals::FingerprintMismatchError) do
      @service.approve(approval_id: approval.id, reviewer: @admin)
    end

    approval.reload
    assert_equal "invalidated", approval.status
  end

  test "Test 18: Policy DENY after approval blocks execution" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    # Add a strict policy rule that denies prepare_payment
    Policy.create!(
      name: "Temporary Freeze on Payments",
      action_key: "prepare_payment",
      effect: "deny",
      conditions: {},
      priority: 1
    )

    assert_raises(Approvals::PolicyRejectionError) do
      @service.approve(approval_id: approval.id, reviewer: @admin)
    end

    approval.reload
    assert_equal "failed", approval.status
    @step.reload
    assert_equal "blocked", @step.status
  end

  test "Test 20 & 22: Duplicate approval decisions and replay attempts are rejected" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    # First decision succeeds
    @service.approve(approval_id: approval.id, reviewer: @admin)

    # Second decision attempt on the same approval raises DuplicateDecisionError
    assert_raises(Approvals::DuplicateDecisionError) do
      @service.approve(approval_id: approval.id, reviewer: @admin)
    end

    assert_raises(Approvals::DuplicateDecisionError) do
      @service.reject(approval_id: approval.id, reviewer: @admin, reason: "Too late")
    end
  end

  test "Test 21: Concurrent approve/reject race condition allows only one successful decision" do
    approval = @service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    results = []
    errors = []

    # Simulate two threads attempting to decide the same approval
    t1 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Approvals::Service.new.approve(approval_id: approval.id, reviewer: @admin)
        results << :approved
      end
    rescue => e
      errors << e
    end

    t2 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Approvals::Service.new.reject(approval_id: approval.id, reviewer: @admin, reason: "Too slow")
        results << :rejected
      end
    rescue => e
      errors << e
    end

    [t1, t2].each(&:join)

    # Exactly one succeeded and the other was rejected with DuplicateDecisionError
    assert_equal 1, results.size
    assert_equal 1, errors.size
    assert_kind_of Approvals::DuplicateDecisionError, errors.first
  end

  test "Test 25: Audit events are generated across all approval actions" do
    assert_difference("AuditEvent.count", 5) do
      # 1. approval_requested
      approval = @service.create_request(
        user: @operator,
        task: @task,
        execution: @execution,
        agent_step: @step,
        action_key: "prepare_payment",
        arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
      )

      # 2. policy_evaluated (revalidation) + 3. approval_approved + 4. approval_consumed + 5. approval_execution_succeeded
      @service.approve(approval_id: approval.id, reviewer: @admin)
    end

    events = AuditEvent.where(approval_id: @step.approvals.last.id).pluck(:event_type)
    assert_includes events, "approval_requested"
    assert_includes events, "approval_approved"
    assert_includes events, "approval_consumed"
    assert_includes events, "approval_execution_succeeded"
  end
end
