require "test_helper"

class GovernedExecutionAcceptanceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @operator = users(:one)
    @admin = users(:two)
    @agent = agents(:financial_agent)

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

  test "End-to-end acceptance: Verify invoice INV-100 and prepare a payment of ₹5,000" do
    # 1. User submits task
    sign_in @operator

    task = @operator.tasks.create!(
      agent: @agent,
      title: "Verify invoice INV-100 and prepare a payment of ₹5,000",
      instruction: "Verify invoice INV-100 and prepare a payment of ₹5,000.",
      submitted_at: Time.current
    )

    assert_equal "pending", task.status

    # Record task creation in audit
    Audit::Recorder.record!(
      event_type: "task_created",
      actor_type: "user",
      actor_id: @operator.id.to_s,
      user: @operator,
      task: task,
      metadata: { instruction: task.instruction }
    )

    # 2 & 3. Structured plan is validated against PlanSchema
    raw_plan = {
      "mode" => "action_plan",
      "response" => "I will verify invoice INV-100 and prepare a payment of ₹5,000.",
      "steps" => [
        { "step_number" => 1, "action" => "lookup_invoice", "description" => "Lookup invoice details", "arguments" => { "invoice_id" => "INV-100" } },
        { "step_number" => 2, "action" => "verify_invoice", "description" => "Verify invoice line items", "arguments" => { "invoice_id" => "INV-100" } },
        { "step_number" => 3, "action" => "prepare_payment", "description" => "Prepare payment voucher", "arguments" => { "invoice_id" => "INV-100", "amount" => 5000 } }
      ],
      "goal" => "Invoice verified and payment prepared."
    }

    normalized_plan = Planning::PlanNormalizer.normalize(raw_plan)
    assert Planning::PlanValidator.validate!(normalized_plan, allowed_tools: %w[lookup_invoice verify_invoice prepare_payment])

    # Create Execution from validated plan
    execution = task.executions.create!(
      agent: @agent,
      status: "running",
      provider: "gemini",
      ai_model: "gemini-3.8-flash",
      plan: normalized_plan,
      started_at: Time.current
    )

    step1 = execution.agent_steps.create!(
      position: 1,
      action_key: "lookup_invoice",
      arguments: { "invoice_id" => "INV-100" },
      status: "pending"
    )

    step2 = execution.agent_steps.create!(
      position: 2,
      action_key: "verify_invoice",
      arguments: { "invoice_id" => "INV-100" },
      status: "pending"
    )

    step3 = execution.agent_steps.create!(
      position: 3,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "pending"
    )

    # 4 & 5. Step 1: Lookup Invoice -> ALLOW -> Execute
    res1 = Tools::Executor.execute(step: step1, user: @operator)
    assert res1.success?
    assert_equal "completed", step1.reload.status
    assert_equal "allow", step1.policy_decision
    assert_equal "INV-100", step1.result["invoice_id"]

    # 6 & 7. Step 2: Verify Invoice -> ALLOW -> Execute
    res2 = Tools::Executor.execute(step: step2, user: @operator)
    assert res2.success?
    assert_equal "completed", step2.reload.status
    assert_equal "allow", step2.policy_decision
    assert_equal true, step2.result["line_items_valid"]

    # 8, 9, 10, 11. Step 3: Prepare Payment -> REQUIRE_APPROVAL -> Paused -> Approval Center
    res3 = Tools::Executor.execute(step: step3, user: @operator)
    assert res3.paused?
    assert_equal "waiting_approval", step3.reload.status
    assert_equal "require_approval", step3.policy_decision
    assert_equal "paused", execution.reload.status

    approval = Approval.find_by(agent_step_id: step3.id)
    assert approval.present?
    assert_equal "pending", approval.status
    assert_equal 5000, approval.action_arguments["amount"]

    # 12. Human in the Loop: Segregation of duties prevents task creator from self-approving
    refute @operator.can_approve?(approval), "Operator must not approve their own payment action"

    # 13, 14, 15, 16. Designated Admin reviews and approves
    sign_in @admin
    assert @admin.can_approve?(approval)

    # Resume approved action
    resume_result = Approvals::Service.approve(approval_id: approval.id, reviewer: @admin)
    assert resume_result.is_a?(Approvals::Decision)
    assert resume_result.approved?

    # 17. Verify execution completed
    approval.reload
    step3.reload
    execution.reload

    assert_equal "executed", approval.status
    assert_equal "completed", step3.status
    assert_equal "completed", execution.status
    assert_equal "voucher_prepared", step3.result["status"]
    assert step3.result["voucher_id"].present?

    # 18. Audit trail completeness and cryptographic SHA-256 chain continuity
    verifier = Audit::IntegrityVerifier.verify_execution(execution.id)
    assert verifier.valid?, "Audit chain must have zero tampering or broken links: #{verifier.errors.join(', ')}"
    assert verifier.total_events >= 5

    # 19. Inspection replay reconstructs history without re-executing tools
    inspection = Replay::ExecutionReplayer.replay(
      execution: execution,
      user: @admin,
      mode: :inspection
    )
    assert inspection.inspection?
    assert_equal 3, inspection.reconstructed_steps.size
    assert inspection.hash_chain_valid

    # 20. Simulation replay uses safe sandbox only
    simulation = Replay::ExecutionReplayer.replay(
      execution: execution,
      user: @admin,
      mode: :simulation
    )
    assert simulation.simulation?
    assert_equal 3, simulation.simulated_steps.size
  end

  test "Acceptance test: ₹15,000 payment request returns DENY" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: tasks(:invoice_task),
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 15000 }
    )

    assert decision.denied?, "₹15,000 exceeds threshold and must be denied"
    assert_equal "payment_limit_rule", decision.policy_id
    assert_includes decision.reason, "exceeds maximum allowable ceiling"
  end

  test "Acceptance test: Unknown tool request returns DENY" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: tasks(:invoice_task),
      action_key: "unauthorized_remote_action",
      arguments: { "id" => "1" }
    )

    assert decision.denied?
  end

  test "Acceptance test: Audit integrity verification detects tampering" do
    # Create execution with audit chain
    execution = tasks(:invoice_task).executions.create!(
      agent: @agent,
      status: "completed"
    )

    event1 = Audit::Recorder.record!(
      execution: execution,
      event_type: "execution_started",
      actor_type: "system",
      actor_id: "test"
    )

    event2 = Audit::Recorder.record!(
      execution: execution,
      event_type: "execution_completed",
      actor_type: "system",
      actor_id: "test"
    )

    chain_id = event1.chain_id

    # Verify clean chain
    assert Audit::IntegrityVerifier.verify_chain(chain_id).valid?

    # Malicious direct database tampering (bypassing Rails application layer)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(["UPDATE audit_events SET metadata = ? WHERE id = ?", { "tampered" => true }.to_json, event2.id])
    )

    # Verification must detect the tampering
    tampered_report = Audit::IntegrityVerifier.verify_chain(chain_id)
    refute tampered_report.valid?, "Verifier must detect modified event hash"
    assert_includes tampered_report.tampered_event_ids, event2.id
  end
end
