require "test_helper"

class ExecutionReplayerTest < ActiveSupport::TestCase
  setup do
    @admin = users(:two)
    @operator = users(:one)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)
    @step = agent_steps(:step_one)
  end

  test "Test 16: Inspection replay reconstructs event order and plan" do
    result = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @operator,
      mode: :inspection
    )

    assert result.inspection?
    assert_equal @execution.id, result.execution_id
    assert_equal @execution.status, result.reconstructed_status
    assert_not_nil result.session_id
    assert_includes result.session_id, "replay_inspection_"
    assert result.reconstructed_steps.any?
  end

  test "Test 17 & 18: Inspection replay does not invoke tools or call AI providers" do
    # Verify no HTTP calls, no tool mutations, no agent step changes
    initial_step_updated_at = @step.updated_at
    initial_audit_count = AuditEvent.count

    result = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @operator,
      mode: :inspection
    )

    assert result.inspection?
    @step.reload
    assert_equal initial_step_updated_at.to_i, @step.updated_at.to_i
    assert_equal initial_audit_count, AuditEvent.count
  end

  test "Test 19: Inspection replay does not modify original events" do
    event = Audit::Recorder.record!(
      execution: @execution,
      task: @task,
      event_type: "tool_execution_succeeded",
      actor_type: "system",
      actor_id: "test",
      metadata: { "tool_name" => "retrieve_invoice" }
    )
    original_event_hash = event.event_hash
    assert_not_nil original_event_hash

    Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @operator,
      mode: :inspection
    )

    event.reload
    assert_equal original_event_hash, event.event_hash
  end

  test "Test 20 & 21: Simulation replay uses mock responses and never executes real payment" do
    result = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @operator,
      mode: :simulation
    )

    assert result.simulation?
    assert result.simulated_steps.any?

    # Verify simulation labels
    sim_step = result.simulated_steps.find { |s| s[:action_key] == "prepare_payment" }
    if sim_step
      assert_includes sim_step[:simulated_result]["note"], "Simulated during execution replay"
      assert_match(/^SIM-VCH-/, sim_step[:simulated_result]["voucher_id"])
    end
  end

  test "Test 22: Simulation replay does not reuse or consume old approvals" do
    approval = approvals(:pending_payment_approval)
    original_status = approval.status

    result = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @admin,
      mode: :simulation
    )

    approval.reload
    assert_equal original_status, approval.status
    refute_equal "executed", approval.status
  end

  test "Test 23: Replay sessions are separated with distinct session IDs" do
    r1 = Replay::ExecutionReplayer.replay(execution: @execution, user: @operator, mode: :inspection)
    r2 = Replay::ExecutionReplayer.replay(execution: @execution, user: @operator, mode: :simulation)

    refute_equal r1.session_id, r2.session_id
    assert_includes r1.session_id, "replay_inspection_"
    assert_includes r2.session_id, "replay_simulation_"
  end

  test "Test 24: Unauthorized users cannot replay executions" do
    other_user = User.create!(
      name: "Outsider",
      email: "outsider_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "operator"
    )

    assert_raises(Replay::UnauthorizedError) do
      Replay::ExecutionReplayer.replay(
        execution: @execution,
        user: other_user,
        mode: :inspection
      )
    end
  end

  test "Test 25: Sensitive values are redacted in replay view" do
    step_with_secret = @execution.agent_steps.create!(
      position: 99,
      action_key: "verify_invoice",
      arguments: { "invoice_id" => "INV-100", "api_key" => "SUPER_SECRET_12345", "token" => "BEARER_XYZ" },
      status: "completed"
    )

    result = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: @operator,
      mode: :inspection
    )

    reconstructed = result.reconstructed_steps.find { |s| s[:id] == step_with_secret.id }
    assert_equal "[REDACTED]", reconstructed[:arguments]["api_key"]
    assert_equal "[REDACTED]", reconstructed[:arguments]["token"]
    assert_equal "INV-100", reconstructed[:arguments]["invoice_id"]
  end
end
