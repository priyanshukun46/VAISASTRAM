require "test_helper"

class ToolsExecutorTest < ActiveSupport::TestCase
  setup do
    @operator = users(:one)
    @admin = users(:two)
    @agent = agents(:financial_agent)
    @task = tasks(:invoice_task)
    @execution = @task.executions.create!(agent: @agent, status: "running", provider: "ollama", ai_model: "gemma3:4b")

    Tool.find_or_create_by!(key: "retrieve_invoice") do |t|
      t.name = "Invoice Retrieval"
      t.risk_level = "low"
      t.enabled = true
      t.required_permission = "invoice:read"
    end

    Tool.find_or_create_by!(key: "prepare_payment") do |t|
      t.name = "Prepare Payment"
      t.risk_level = "high"
      t.enabled = true
      t.required_permission = "payment:prepare"
    end

    Tool.find_or_create_by!(key: "delete_financial_record") do |t|
      t.name = "Delete Financial Record"
      t.risk_level = "critical"
      t.enabled = true
      t.required_permission = "admin:delete_records"
    end
  end

  test "ALLOW decision executes tool and marks step completed" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @operator)

    assert result.success?
    refute result.blocked?
    refute result.paused?
    assert_equal "completed", step.reload.status
    assert_equal "allow", step.policy_decision
    assert_equal "retrieved", step.result["status"]
    assert_equal "INV-100", step.result["invoice_id"]
    assert_not_nil step.completed_at
  end

  test "REQUIRE_APPROVAL decision pauses execution, creates Approval record, and marks step waiting_approval" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @operator)

    assert result.paused?
    refute result.success?
    refute result.blocked?

    # Verify step and execution states
    step.reload
    assert_equal "waiting_approval", step.status
    assert_equal "require_approval", step.policy_decision
    assert_equal "paused", @execution.reload.status

    # Verify Approval record generated with action fingerprint
    assert_not_nil result.approval
    assert_equal step.id, result.approval.agent_step_id
    assert_equal "pending", result.approval.status
    assert_equal result.decision.action_fingerprint, result.approval.action_digest
  end

  test "DENY decision terminates action, blocks execution, and marks step blocked" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 50000 }, # Exceeds ₹10k
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @operator)

    assert result.blocked?
    refute result.success?
    refute result.paused?

    # Step and execution must be blocked
    step.reload
    assert_equal "blocked", step.status
    assert_equal "deny", step.policy_decision
    assert_equal "blocked", @execution.reload.status
    assert_includes step.result["error"], "Blocked by policy engine"
    assert_includes step.result["error"], "exceeds maximum allowable ceiling"
  end

  test "DENY on sensitive operation blocks destructive action" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "delete_financial_record",
      arguments: { "target" => "all_invoices" },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @admin)

    assert result.blocked?
    assert_equal "blocked", step.reload.status
    assert_equal "blocked", @execution.reload.status
  end

  # =========================================================
  # Test 16: Executor cannot bypass the policy engine
  # =========================================================
  test "Test 16: executor cannot bypass the policy engine" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "delete_financial_record",
      arguments: { "target" => "all_invoices" },
      status: "pending"
    )

    # Even if someone attempts to pass a mocked ALLOW decision directly to private handlers,
    # the executor raises PolicyBypassError
    assert_raises(Tools::PolicyBypassError) do
      executor = Tools::Executor.new(step: step, user: @operator)
      fake_decision = Object.new
      fake_decision.define_singleton_method(:allowed?) { true }
      executor.send(:handle_allow!, fake_decision)
    end
  end

  test "policy engine evaluation failure blocks tool execution" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" },
      status: "pending"
    )

    failing_evaluator = Object.new
    failing_evaluator.define_singleton_method(:evaluate) do |_ctx|
      raise StandardError.new("Policy Engine database lock timeout")
    end

    begin
      Policies::Engine.custom_evaluator = failing_evaluator
      result = Tools::Executor.execute(step: step, user: @operator)

      assert result.failed?
      step.reload
      assert_equal "failed", step.status
      assert_equal "failed", @execution.reload.status
      assert_includes step.result["error"], "Policy Engine database lock timeout"
    ensure
      Policies::Engine.custom_evaluator = nil
    end
  end
end
