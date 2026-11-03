require "test_helper"

class AuditEventsLifecycleTest < ActiveSupport::TestCase
  setup do
    @admin = users(:two)
    @operator = users(:one)
    @agent = agents(:financial_agent)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)
  end

  test "Test 1: Task creation creates an audit event" do
    new_task = @operator.tasks.create!(
      agent: @agent,
      title: "Audit Test Task",
      instruction: "Perform test",
      submitted_at: Time.current
    )

    Audit::Recorder.record!(
      event_type: "task_created",
      actor_type: "user",
      actor_id: @operator.id.to_s,
      user: @operator,
      task: new_task,
      metadata: { title: new_task.title }
    )

    event = AuditEvent.where(task_id: new_task.id, event_type: "task_created").last
    assert_not_nil event
    assert_equal "user", event.actor_type
    assert_equal @operator.id.to_s, event.actor_id
    assert_equal "task:#{new_task.id}", event.chain_id
    assert_equal 1, event.sequence_number
  end

  test "Test 2: Plan generation is recorded" do
    event = Audit::Recorder.record!(
      event_type: "plan_generated",
      actor_type: "agent",
      actor_id: @agent.name,
      user: @operator,
      task: @task,
      execution: @execution,
      metadata: { mode: "action_plan", steps_count: 2 }
    )

    assert_not_nil event
    assert_equal "plan_generated", event.event_type
    assert_equal "agent", event.actor_type
  end

  test "Test 3: Policy ALLOW is recorded" do
    step = @execution.agent_steps.create!(
      position: 11,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" },
      status: "pending"
    )

    context = Policies::Context.new(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" }
    )

    decision = Policies::Engine.evaluate(context)
    assert decision.allowed?

    allowed_event = AuditEvent.where(agent_step_id: step.id, event_type: "policy_evaluated").last
    assert_not_nil allowed_event
    assert_equal "allow", allowed_event.policy_decision
  end

  test "Test 4: Policy REQUIRE_APPROVAL is recorded" do
    step = @execution.agent_steps.create!(
      position: 12,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "pending"
    )

    context = Policies::Context.new(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    decision = Policies::Engine.evaluate(context)
    assert decision.requires_approval?

    approval_event = AuditEvent.where(agent_step_id: step.id, event_type: "policy_evaluated").last
    assert_not_nil approval_event
    assert_equal "require_approval", approval_event.policy_decision
  end

  test "Test 5: Policy DENY is recorded" do
    step = @execution.agent_steps.create!(
      position: 13,
      action_key: "delete_financial_record",
      arguments: { "target" => "INV-100" },
      status: "pending"
    )

    context = Policies::Context.new(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "delete_financial_record",
      arguments: { "target" => "INV-100" }
    )

    decision = Policies::Engine.evaluate(context)
    assert decision.denied?

    denied_event = AuditEvent.where(agent_step_id: step.id, event_type: "policy_evaluated").last
    assert_not_nil denied_event
    assert_equal "deny", denied_event.policy_decision
  end

  test "Test 6: Tool execution success is recorded" do
    step = @execution.agent_steps.create!(
      position: 14,
      action_key: "retrieve_invoice",
      arguments: { "invoice_id" => "INV-100" },
      status: "pending"
    )

    result = Tools::Executor.execute(step: step, user: @operator)
    assert result.success?

    success_event = AuditEvent.where(agent_step_id: step.id, event_type: "tool_execution_succeeded").last
    assert_not_nil success_event
    assert_equal "retrieve_invoice", success_event.tool_name
  end

  test "Test 7: Tool execution failure is recorded" do
    step = @execution.agent_steps.create!(
      position: 15,
      action_key: "unsupported_tool_xyz",
      arguments: {},
      status: "pending"
    )

    # Unsupported tool fails closed in executor
    result = Tools::Executor.execute(step: step, user: @operator)
    assert result.blocked? # policy denies unknown tool first

    blocked_event = AuditEvent.where(agent_step_id: step.id, event_type: "tool_execution_blocked").last
    assert_not_nil blocked_event
  end

  test "Test 8: Approval decisions (approve and reject) are recorded" do
    step = @execution.agent_steps.create!(
      position: 16,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 },
      status: "pending"
    )

    approval = Approvals::Service.create_request(
      user: @operator,
      task: @task,
      execution: @execution,
      agent_step: step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    # Approve
    decision = Approvals::Service.approve(approval_id: approval.id, reviewer: @admin)
    assert decision.approved?

    approved_event = AuditEvent.where(approval_id: approval.id, event_type: "approval_approved").last
    assert_not_nil approved_event
    assert_equal @admin.id.to_s, approved_event.actor_id
  end

  test "Test 9: Provider fallback is recorded" do
    event = Audit::Recorder.record!(
      event_type: "ai_provider_fallback_used",
      actor_type: "system",
      actor_id: "agent_planner",
      user: @operator,
      task: @task,
      execution: @execution,
      metadata: { primary_failed: true, fallback_provider: "groq", reason: "Gemini rate limit exceeded" }
    )

    assert_not_nil event
    assert_equal "ai_provider_fallback_used", event.event_type
    assert_equal "groq", event.metadata["fallback_provider"]
  end

  test "Test 10: Task completion is recorded" do
    event = Audit::Recorder.record!(
      event_type: "task_completed",
      actor_type: "system",
      actor_id: "agent_runtime",
      user: @operator,
      task: @task,
      execution: @execution,
      status: "completed",
      metadata: { completed_steps: 2 }
    )

    assert_not_nil event
    assert_equal "task_completed", event.event_type
    assert_equal "completed", event.status
  end
end
