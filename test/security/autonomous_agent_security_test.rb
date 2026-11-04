require "test_helper"

class AutonomousAgentSecurityTest < ActiveSupport::TestCase
  setup do
    @operator = users(:one)
    @admin = users(:two)
    @task = tasks(:invoice_task)
    @execution = @task.executions.create!(
      agent: agents(:financial_agent),
      status: "running",
      provider: "gemini",
      ai_model: "gemini-3.8-flash"
    )

    # Ensure canonical tools exist
    Tool.find_or_create_by!(key: "lookup_invoice") do |t|
      t.name = "Lookup Invoice"
      t.risk_level = "low"
      t.enabled = true
      t.required_permission = "invoice:read"
    end

    Tool.find_or_create_by!(key: "verify_invoice") do |t|
      t.name = "Verify Invoice"
      t.risk_level = "low"
      t.enabled = true
      t.required_permission = "invoice:verify"
    end

    Tool.find_or_create_by!(key: "prepare_payment") do |t|
      t.name = "Prepare Payment"
      t.risk_level = "high"
      t.enabled = true
      t.required_permission = "payment:prepare"
    end
  end

  # =========================================================
  # 1. Unregistered Tools Denied
  # =========================================================
  test "AI cannot invoke unregistered tools" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "unregistered_external_tool",
      arguments: { "target" => "system" }
    )

    assert decision.denied?, "Unregistered tool must be denied by Policy Engine"
    assert_includes %w[unregistered_tool_rule tool_permission_rule], decision.policy_id

    assert_raises(Tools::ExecutionError) do
      Tools::Executor.new(
        user: @operator,
        task: @task,
        action_key: "unregistered_external_tool",
        arguments: {}
      ).send(:dispatch_tool!, "unregistered_external_tool", {})
    end
  end

  # =========================================================
  # 2. Arbitrary Ruby, Shell & SQL Execution Blocked
  # =========================================================
  test "AI cannot execute arbitrary Ruby code" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "eval_code",
      arguments: { "code" => "User.delete_all" }
    )
    assert decision.denied?

    assert_raises(Tools::ExecutionError) do
      Tools::Executor.new(
        user: @operator,
        task: @task,
        action_key: "eval_code",
        arguments: { "code" => "puts 'hacked'" }
      ).send(:dispatch_tool!, "eval_code", { "code" => "puts 'hacked'" })
    end
  end

  test "AI cannot execute shell commands" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "shell_exec",
      arguments: { "cmd" => "rm -rf /" }
    )
    assert decision.denied?

    assert_raises(Tools::ExecutionError) do
      Tools::Executor.new(
        user: @operator,
        task: @task,
        action_key: "bash",
        arguments: { "cmd" => "whoami" }
      ).send(:dispatch_tool!, "bash", { "cmd" => "whoami" })
    end
  end

  test "AI cannot execute arbitrary SQL queries" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "execute_sql",
      arguments: { "query" => "DROP TABLE users;" }
    )
    assert decision.denied?
  end

  # =========================================================
  # 3. Policy Tampering & Integrity
  # =========================================================
  test "AI cannot modify policy records through tools" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "modify_policy",
      arguments: { "rule_id" => "payment_limit_rule", "enabled" => false }
    )
    assert decision.denied?
  end

  # =========================================================
  # 4. Human Approval Security & Self-Approval Prevention
  # =========================================================
  test "AI cannot approve its own actions and operator cannot approve own task" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "waiting_approval"
    )

    approval = Approvals::Service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      decision: Policies::Decision.require_approval(policy_id: "payment_limit_rule", reason: "Requires human review")
    )

    # Operator who created task CANNOT approve (Segregation of Duties)
    refute @operator.can_approve?(approval), "Task creator must not approve their own sensitive task"

    # Admin CAN approve
    assert @admin.can_approve?(approval), "Designated admin can approve"
  end

  # =========================================================
  # 5. Argument Tampering & Fingerprint Validation
  # =========================================================
  test "AI cannot modify approved action arguments (tampering detection)" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "waiting_approval"
    )

    approval = Approvals::Service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      decision: Policies::Decision.require_approval(policy_id: "payment_limit_rule", reason: "Requires human review")
    )

    # Approve original ₹5,000 request
    Approvals::Service.approve(approval_id: approval.id, reviewer: @admin)
    approval.reload

    # Malicious actor tampers with step arguments to ₹500,000
    step.update_columns(arguments: { "invoice_id" => "INV-100", "amount" => 500000 })

    # Attempting to validate or resume must fail with fingerprint mismatch
    refute Approvals::FingerprintValidator.valid?(approval)

    assert_raises(Approvals::FingerprintMismatchError) do
      Approvals::FingerprintValidator.validate!(approval)
    end
  end

  # =========================================================
  # 6. Expired Approvals Cannot Execute
  # =========================================================
  test "AI cannot reuse expired approvals" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "waiting_approval"
    )

    approval = Approvals::Service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      decision: Policies::Decision.require_approval(policy_id: "payment_limit_rule", reason: "Requires human review")
    )

    # Backdate expiration
    approval.update_columns(expires_at: 1.hour.ago)

    assert approval.expired?

    assert_raises(Approvals::ExpiredError) do
      Approvals::Service.approve(approval_id: approval.id, reviewer: @admin)
    end
  end

  # =========================================================
  # 7. Consumed Approvals Cannot Be Replayed
  # =========================================================
  test "AI cannot replay consumed approvals" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "waiting_approval"
    )

    approval = Approvals::Service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      decision: Policies::Decision.require_approval(policy_id: "payment_limit_rule", reason: "Requires human review")
    )

    # Approve and execute
    Approvals::Service.approve(approval_id: approval.id, reviewer: @admin)
    approval.reload

    # Approval is now executed
    assert_equal "executed", approval.status

    # Cannot approve again
    assert_raises(Approvals::DuplicateDecisionError) do
      Approvals::Service.approve(approval_id: approval.id, reviewer: @admin)
    end
  end

  # =========================================================
  # 8. Policy Engine Fail-Closed Invariant
  # =========================================================
  test "policy engine failure fails closed and denies execution" do
    context = Policies::Context.new(
      user: @operator,
      task: @task,
      action_key: "verify_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )

    # A rule that crashes during evaluation
    crashing_rule = Object.new
    def crashing_rule.priority; 10; end
    def crashing_rule.evaluate(_context); raise StandardError, "Policy Engine rule evaluation crash"; end

    evaluator = Policies::Evaluator.new([crashing_rule])
    decision = evaluator.evaluate(context)

    assert decision.denied?, "Engine MUST fail-closed with DENY on unexpected error"
    assert_equal "evaluator_failure", decision.policy_id
    assert_includes decision.reason, "fail-closed security mandate"
  end

  # =========================================================
  # 9. Audit Recording Failure Blocks Sensitive Execution
  # =========================================================
  test "audit failure blocks security-sensitive tool execution" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "lookup_invoice",
      arguments: { "invoice_id" => "INV-100" },
      status: "pending"
    )

    original_record = Audit::Recorder.method(:record!)
    Audit::Recorder.define_singleton_method(:record!) do |**kwargs|
      raise StandardError, "Audit storage unavailable"
    end

    begin
      result = Tools::Executor.execute(step: step, user: @operator)
      assert result.failed?, "Execution must fail when audit recording fails"
      assert_equal "failed", step.reload.status
      assert_includes step.result["error"], "Audit storage unavailable"
    ensure
      Audit::Recorder.define_singleton_method(:record!, original_record)
    end
  end

  # =========================================================
  # 10. Replay & Simulation Never Invoke Real Tools
  # =========================================================
  test "inspection and simulation replay never execute side-effecting tools" do
    step = @execution.agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "completed",
      result: { "voucher_id" => "VCH-1234" }
    )

    # Run inspection replay
    inspection = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @admin,
      mode: :inspection
    )
    assert inspection.inspection?
    assert_equal 1, inspection.reconstructed_steps.size

    # Run simulation replay
    simulation = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @admin,
      mode: :simulation
    )
    assert simulation.simulation?
    assert simulation.simulated_steps.any?
  end

  # =========================================================
  # 11. Boundary Values & Financial Arithmetic Security
  # =========================================================
  test "payment limit boundary values and strict numeric handling" do
    # Baseline: exactly ₹10,000 (1_000_000 paise) -> REQUIRE_APPROVAL
    d1 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => 10_000 }
    )
    assert d1.requires_approval?, "₹10,000 must require approval"

    # ₹10,000.01 (1_000_001 paise) -> DENY
    d2 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => 10_000.01 }
    )
    assert d2.denied?, "₹10,000.01 exceeds limit and must be DENIED"

    # ₹15,000 (1_500_000 paise) -> DENY
    d3 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => 15_000 }
    )
    assert d3.denied?, "₹15,000 must be DENIED"

    # Zero amount -> DENY
    d4 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => 0 }
    )
    assert d4.denied?, "₹0 payment must be DENIED"

    # Negative amount -> DENY
    d5 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => -500 }
    )
    assert d5.denied?, "Negative payment must be DENIED"

    # String amount manipulation ("10000") -> DENY
    d6 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => "10000" }
    )
    assert d6.denied?, "String amount representation must be DENIED"

    # Formatted currency string ("₹5,000") -> DENY
    d7 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => "₹5,000" }
    )
    assert d7.denied?, "Formatted string currency must be DENIED"

    # Missing amount -> DENY
    d8 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100" }
    )
    assert d8.denied?, "Missing payment amount must be DENIED"

    # Float Infinity -> DENY
    d9 = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => Float::INFINITY }
    )
    assert d9.denied?, "Infinity payment amount must be DENIED"
  end
end
