require "test_helper"

class PoliciesEngineTest < ActiveSupport::TestCase
  setup do
    @operator = users(:one)
    @admin = users(:two)
    @agent = agents(:financial_agent)
    @task = tasks(:invoice_task)

    # Ensure required tools exist in test database
    Tool.find_or_create_by!(key: "retrieve_invoice") do |t|
      t.name = "Invoice Retrieval"
      t.risk_level = "low"
      t.enabled = true
      t.required_permission = "invoice:read"
    end

    Tool.find_or_create_by!(key: "verify_invoice") do |t|
      t.name = "Invoice Verification"
      t.risk_level = "low"
      t.enabled = true
      t.required_permission = "invoice:verify"
    end

    Tool.find_or_create_by!(key: "get_vendor") do |t|
      t.name = "Vendor Lookup"
      t.risk_level = "low"
      t.enabled = true
      t.required_permission = "vendor:read"
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

  # =========================================================
  # Test 1: Invoice retrieval allowed
  # =========================================================
  test "Test 1: invoice retrieval allowed" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )

    assert decision.allowed?
    refute decision.denied?
    refute decision.requires_approval?
    assert_equal Policies::Decision::ALLOW, decision.decision
    assert_includes decision.reason, "allowlisted for autonomous execution"
  end

  # =========================================================
  # Test 2: Invoice verification allowed
  # =========================================================
  test "Test 2: invoice verification allowed" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "verify_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )

    assert decision.allowed?
    refute decision.denied?
    refute decision.requires_approval?
    assert_equal Policies::Decision::ALLOW, decision.decision
  end

  # =========================================================
  # Test 3: Vendor lookup allowed
  # =========================================================
  test "Test 3: vendor lookup allowed" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "get_vendor",
      arguments: { "vendor_id" => "VND-100" }
    )

    assert decision.allowed?
    refute decision.denied?
    refute decision.requires_approval?
    assert_equal Policies::Decision::ALLOW, decision.decision
  end

  # =========================================================
  # Test 4: Payment below or equal to threshold requires approval (<= ₹10,000)
  # =========================================================
  test "Test 4: payment below threshold requires approval" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    assert decision.requires_approval?
    refute decision.allowed?
    refute decision.denied?
    assert_equal Policies::Decision::REQUIRE_APPROVAL, decision.decision
    assert_includes decision.reason, "requires human operator approval"
    assert_equal 500000, decision.matched_conditions[:amount_paise] # 5000 * 100 paise
  end

  test "Test 4b: payment exactly at ₹10,000 threshold requires approval" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 10000 }
    )

    assert decision.requires_approval?
    refute decision.denied?
    assert_equal Policies::Decision::REQUIRE_APPROVAL, decision.decision
  end

  # =========================================================
  # Test 5: Payment above threshold denied (> ₹10,000)
  # =========================================================
  test "Test 5: payment above threshold denied" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 10001 }
    )

    assert decision.denied?
    refute decision.allowed?
    refute decision.requires_approval?
    assert_equal Policies::Decision::DENY, decision.decision
    assert_includes decision.reason, "exceeds maximum allowable ceiling of ₹10,000"
  end

  # =========================================================
  # Test 6: Unknown tool denied
  # =========================================================
  test "Test 6: unknown tool denied" do
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "unknown_external_tool_xyz",
      arguments: {}
    )

    assert decision.denied?
    refute decision.allowed?
    assert_equal Policies::Decision::DENY, decision.decision
    assert_includes decision.reason, "unregistered tool 'unknown_external_tool_xyz' is denied"
  end

  # =========================================================
  # Test 7: Missing user context denied
  # =========================================================
  test "Test 7: missing user context denied" do
    decision = Policies::Engine.evaluate(
      user: nil,
      task: @task,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )

    assert decision.denied?
    refute decision.allowed?
    assert_equal Policies::Decision::DENY, decision.decision
    assert_includes decision.reason, "Missing required authenticated user context"
  end

  # =========================================================
  # Test 8: Malformed arguments denied
  # =========================================================
  test "Test 8: malformed arguments denied" do
    # Missing amount
    missing_amount = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100" }
    )
    assert missing_amount.denied?
    assert_includes missing_amount.reason, "Missing payment amount"

    # Negative amount
    negative_amount = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => -500 }
    )
    assert negative_amount.denied?
    assert_includes negative_amount.reason, "greater than zero"

    # Zero amount
    zero_amount = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 0 }
    )
    assert zero_amount.denied?
    assert_includes zero_amount.reason, "greater than zero"
  end

  # =========================================================
  # Test 9: String amount manipulation rejected
  # =========================================================
  test "Test 9: string amount manipulation rejected" do
    string_attempts = [
      "1000",
      "10000",
      "5000.00",
      "₹5,000",
      "5,000",
      "1e4",
      "10000; DROP TABLE users;",
      "0x2710"
    ]

    string_attempts.each do |sneaky_str|
      decision = Policies::Engine.evaluate(
        user: @operator,
        task: @task,
        action_key: "prepare_payment",
        arguments: { "invoice_id" => "INV-100", "amount" => sneaky_str }
      )

      assert decision.denied?, "Expected string amount '#{sneaky_str}' to be denied"
      assert_includes decision.reason, "Payment amount cannot be a string representation; numeric value required"
    end
  end

  # =========================================================
  # Test 10: Explicit deny overrides allow
  # =========================================================
  test "Test 10: explicit deny overrides allow" do
    # Create an explicit user or system policy that denies retrieve_invoice for a specific condition
    override_policy = Policy.create!(
      name: "Temporary Embargo on Invoice Retrieval",
      action_key: "retrieve_invoice",
      effect: "deny",
      priority: 5, # higher priority than general allow
      conditions: {},
      enabled: true
    )

    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )

    assert decision.denied?
    refute decision.allowed?
    assert_equal Policies::Decision::DENY, decision.decision
    assert_includes decision.reason, "Temporary Embargo on Invoice Retrieval"
  ensure
    override_policy&.destroy
  end

  # =========================================================
  # Test 11: AI risk labels ignored
  # =========================================================
  test "Test 11: AI risk labels ignored" do
    # Suppose an AI tries to bypass policies by tagging excessive payment as 'low' risk
    # or claiming authorized: true in step arguments or step model
    step = @task.executions.create!(agent: @agent, status: "running").agent_steps.create!(
      position: 1,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 25000, "ai_risk_level" => "low", "ai_status" => "authorized" },
      risk_level: "low" # AI claimed low risk!
    )

    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      agent_step: step,
      action_key: step.action_key,
      arguments: step.arguments
    )

    # Ruby policy engine must completely ignore the AI's 'low' label and DENY because amount > ₹10k
    assert decision.denied?
    refute decision.allowed?
    assert_equal Policies::Decision::DENY, decision.decision
    assert_includes decision.reason, "exceeds maximum allowable ceiling of ₹10,000"
  end

  # =========================================================
  # Test 12: Policy engine failure blocks execution
  # =========================================================
  test "Test 12: policy engine failure blocks execution" do
    broken_rule = Object.new
    broken_rule.define_singleton_method(:priority) { 20 }
    broken_rule.define_singleton_method(:evaluate) do |context|
      raise RuntimeError, "Database connection failure during policy evaluation"
    end

    custom_evaluator = Policies::Evaluator.new([broken_rule])

    Policies::Engine.custom_evaluator = custom_evaluator
    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )
  ensure
    Policies::Engine.custom_evaluator = nil

    # Must fail closed with DENY!
    assert decision.denied?
    refute decision.allowed?
    assert_equal Policies::Decision::DENY, decision.decision
    assert_includes decision.reason, "Policy engine failure"
    assert_includes decision.reason, "Database connection failure"
  end

  # =========================================================
  # Test 13: Action fingerprint stability
  # =========================================================
  test "Test 13: action fingerprint stability" do
    fingerprint1 = Policies::Fingerprint.generate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    fingerprint2 = Policies::Fingerprint.generate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "amount" => 5000, "invoice_id" => "INV-100" } # different key order
    )

    assert_not_nil fingerprint1
    assert_equal 64, fingerprint1.length
    assert_equal fingerprint1, fingerprint2, "Fingerprint must be stable regardless of key order"
  end

  # =========================================================
  # Test 14: Different arguments generate different fingerprints
  # =========================================================
  test "Test 14: different arguments generate different fingerprints" do
    fingerprint_a = Policies::Fingerprint.generate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    fingerprint_b = Policies::Fingerprint.generate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 6000 }
    )

    refute_equal fingerprint_a, fingerprint_b
  end

  # =========================================================
  # Test 15: Different users generate different fingerprints
  # =========================================================
  test "Test 15: different users generate different fingerprints" do
    fingerprint_operator = Policies::Fingerprint.generate(
      user: @operator,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    fingerprint_admin = Policies::Fingerprint.generate(
      user: @admin,
      task: @task,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    refute_equal fingerprint_operator, fingerprint_admin
  end

  # =========================================================
  # Test 17: Every decision generates an audit record
  # =========================================================
  test "Test 17: every decision generates an audit record" do
    initial_count = AuditEvent.count

    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )

    assert_equal initial_count + 1, AuditEvent.count

    audit = AuditEvent.last
    assert_equal "policy_evaluated", audit.event_type
    assert_equal "policy_engine", audit.actor_type
    assert_equal @operator.id, audit.user_id
    assert_equal decision.policy_id, audit.actor_id
    assert_equal "allow", audit.metadata["decision"]
    assert_equal decision.action_fingerprint, audit.metadata["action_fingerprint"]
    assert_equal "retrieve_invoice", audit.metadata["action_key"]
  end

  # =========================================================
  # Test 18: Disabled policies cannot authorize actions
  # =========================================================
  test "Test 18: disabled policies cannot authorize actions" do
    # Disable all system policies for retrieve_invoice
    Policy.where(action_key: "retrieve_invoice").update_all(enabled: false)
    # Also disable the tool permission rule's allow by testing a custom action that only has a disabled policy
    custom_policy = Policy.create!(
      name: "Special Tool Access",
      action_key: "custom_special_tool",
      effect: "allow",
      priority: 10,
      enabled: false # DISABLED
    )

    decision = Policies::Engine.evaluate(
      user: @operator,
      task: @task,
      action_key: "custom_special_tool",
      arguments: {}
    )

    # Because policy is disabled and tool is unallowlisted, must fail closed with DENY
    assert decision.denied?
    refute decision.allowed?
    assert_equal Policies::Decision::DENY, decision.decision
  ensure
    Policy.where(action_key: "retrieve_invoice").update_all(enabled: true)
    custom_policy&.destroy
  end

  # =========================================================
  # Sensitive Operation Test: Record Deletion Denied
  # =========================================================
  test "sensitive operations like delete_financial_record are hard denied" do
    decision = Policies::Engine.evaluate(
      user: @admin, # even for admin!
      task: @task,
      action_key: "delete_financial_record",
      arguments: { "target" => "invoices_2025" }
    )

    assert decision.denied?
    refute decision.allowed?
    assert_includes decision.reason, "strictly prohibited by security governance"
  end
end
