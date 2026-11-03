require "test_helper"

class AgentPlannerTest < ActiveSupport::TestCase
  class MockRouter
    attr_accessor :response_data, :error_to_raise, :calls

    def initialize(response_data = nil, error_to_raise: nil)
      @response_data = response_data
      @error_to_raise = error_to_raise
      @calls = 0
    end

    def generate(prompt, options = {})
      @calls += 1
      raise @error_to_raise if @error_to_raise

      Ai::Response.new(
        raw_content: @response_data.to_json,
        data: @response_data,
        provider: "gemini",
        model: "gemini-2.5-pro",
        duration_ms: 150.0
      )
    end
  end

  setup do
    @user = users(:one)
    @admin = users(:two)
    @agent = agents(:financial_agent)
    @task = tasks(:invoice_task)

    # Ensure tools exist in test DB
    Tool.find_or_create_by!(key: "lookup_invoice") do |t|
      t.name = "Lookup Invoice"
      t.risk_level = "low"
      t.enabled = true
    end

    Tool.find_or_create_by!(key: "verify_invoice") do |t|
      t.name = "Verify Invoice"
      t.risk_level = "low"
      t.enabled = true
    end

    Tool.find_or_create_by!(key: "prepare_payment") do |t|
      t.name = "Prepare Payment"
      t.risk_level = "high"
      t.enabled = true
    end

    @valid_plan_data = {
      "mode" => "action_plan",
      "goal" => "Verify invoice INV-100 and prepare payment",
      "response" => "I will verify invoice INV-100 and prepare a payment voucher for approval.",
      "summary" => "Retrieve, verify, and prepare payment voucher.",
      "steps" => [
        {
          "step_number" => 1,
          "action" => "lookup_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Fetch invoice record"
        },
        {
          "step_number" => 2,
          "action" => "verify_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Validate invoice details"
        },
        {
          "step_number" => 3,
          "action" => "prepare_payment",
          "arguments" => { "invoice_id" => "INV-100", "amount" => 5000 },
          "description" => "Prepare disbursement voucher"
        }
      ]
    }
  end

  test "successful plan generation transitions task and execution to planned" do
    router = MockRouter.new(@valid_plan_data)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?
    assert_equal 1, router.calls

    # Task & Execution state
    @task.reload
    assert_equal "planned", @task.status
    assert_equal "planned", result.execution.status
    assert_equal "gemini", result.execution.provider
    assert_equal "gemini-2.5-pro", result.execution.ai_model
    assert_equal @valid_plan_data["goal"], result.execution.plan["goal"]

    # Steps created
    assert_equal 3, result.steps.size
    assert_equal 1, result.steps[0].position
    assert_equal "lookup_invoice", result.steps[0].action_key
    assert_equal "pending", result.steps[0].status
    assert_equal "unknown", result.steps[0].risk_level

    assert_equal 2, result.steps[1].position
    assert_equal "verify_invoice", result.steps[1].action_key

    assert_equal 3, result.steps[2].position
    assert_equal "prepare_payment", result.steps[2].action_key

    # Audit event recorded
    audit = AuditEvent.where(execution: result.execution, event_type: "plan_generated").last
    assert_not_nil audit
    assert_equal @user, audit.user
    assert_equal @agent.name, audit.actor_id
    assert_equal 3, audit.metadata["steps_count"]
  end

  test "no tool execution occurs during planning" do
    router = MockRouter.new(@valid_plan_data)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?

    # Verify that every single step is merely proposed and strictly in pending status
    result.steps.each do |step|
      assert_equal "pending", step.status, "Steps must remain pending during planning"
      assert_equal "unknown", step.risk_level, "Risk must not be determined by the planner"
      assert_nil step.policy_decision, "Policy decision must not exist during planning"
      assert_empty step.result, "Tool results must be empty during planning"
      assert_nil step.started_at, "Step must not have started"
      assert_nil step.completed_at, "Step must not have completed"
    end
  end

  test "rejects cross-user task access" do
    other_user = User.create!(name: "Unauthorized Operator", email: "unauthorized@vaisastram.internal", password: "password123", role: "operator")
    router = MockRouter.new(@valid_plan_data)

    assert_raises(Planning::UnauthorizedError) do
      Planning::AgentPlanner.plan(task: @task, user: other_user, provider_router: router)
    end

    # Verify task was not altered
    @task.reload
    assert_not_equal "planning", @task.status
    assert_not_equal "planned", @task.status
    assert_equal 0, router.calls
  end

  test "admin can plan tasks belonging to any user" do
    router = MockRouter.new(@valid_plan_data)
    result = Planning::AgentPlanner.plan(task: @task, user: @admin, provider_router: router)

    assert result.success?
    @task.reload
    assert_equal "planned", @task.status
  end

  test "handles AI provider failure gracefully" do
    failing_router = MockRouter.new(nil, error_to_raise: Ai::AllProvidersFailedError.new("All AI providers down"))
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: failing_router)

    assert result.failure?
    assert_includes result.error_message, "All AI providers down"

    @task.reload
    assert_equal "failed", @task.status
    assert_equal "failed", result.execution.status
    assert_includes result.execution.error_message, "All AI providers down"

    # Verify failure audit event
    audit = AuditEvent.where(execution: result.execution, event_type: "planning_failed").last
    assert_not_nil audit
    assert_equal "system", audit.actor_type
  end

  test "rejects invalid AI plan output (e.g. unknown action proposed in injection attack)" do
    injection_plan = @valid_plan_data.deep_dup
    # AI proposes an unauthorized tool
    injection_plan["steps"][0]["action"] = "shell_execute"

    router = MockRouter.new(injection_plan)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.failure?
    assert_includes result.error_message, "unknown or disallowed action 'shell_execute'"

    @task.reload
    assert_equal "failed", @task.status
    assert_equal "failed", result.execution.status

    # No AgentStep records created for invalid plan
    assert_equal 0, result.execution.agent_steps.count
  end

  test "returns human-readable response text and structured plan simultaneously" do
    plan_with_response = @valid_plan_data.merge(
      "response" => "I have planned 3 actions to lookup, verify, and prepare payment for invoice INV-100. Please review before policy check.",
      "requires_action" => true
    )

    router = MockRouter.new(plan_with_response)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?
    assert result.requires_action?
    assert_equal "I have planned 3 actions to lookup, verify, and prepare payment for invoice INV-100. Please review before policy check.", result.response_text
    assert_equal 3, result.steps.size
    assert_equal "lookup_invoice", result.steps[0].action_key
  end

  test "handles conversational clarification request when essential info is missing" do
    clarification_data = {
      "response" => "Could you please specify which invoice ID you would like me to process?",
      "requires_action" => false,
      "goal" => "Clarification needed",
      "summary" => "Missing invoice identifier",
      "steps" => [],
      "clarification_needed" => "Invoice ID is missing."
    }

    router = MockRouter.new(clarification_data)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?
    assert_not result.requires_action?
    assert result.clarification_needed?
    assert_equal "Could you please specify which invoice ID you would like me to process?", result.response_text
    assert_equal 0, result.steps.size
    assert_equal "planned", @task.reload.status
  end

  test "handles conversational explanation when action cannot be planned" do
    unplannable_data = {
      "response" => "I cannot delete production server records as this tool is not permit-listed.",
      "requires_action" => false,
      "goal" => "Unplannable request",
      "summary" => "Requested action is outside allowlisted capabilities.",
      "steps" => [],
      "explanation" => "Prohibited action key."
    }

    router = MockRouter.new(unplannable_data)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?
    assert_not result.requires_action?
    assert_equal "I cannot delete production server records as this tool is not permit-listed.", result.response_text
    assert_equal "Prohibited action key.", result.explanation
    assert_equal 0, result.steps.size
  end

  test "rejects AI planner response that falsely implies execution has already completed" do
    hallucinated_plan = @valid_plan_data.merge(
      "response" => "I have executed the payment of ₹5,000 for invoice INV-100."
    )

    router = MockRouter.new(hallucinated_plan)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.failure?
    assert_includes result.error_message, "falsely implies actions have already been executed"
    assert_equal "failed", @task.reload.status
  end

  test "rejects AI planner response missing required 'goal' field" do
    missing_goal_plan = @valid_plan_data.except("goal")

    router = MockRouter.new(missing_goal_plan)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.failure?
    assert_includes result.error_message, "Missing required field 'goal'"
    assert_equal "failed", @task.reload.status
    assert_equal "failed", result.execution.status
    assert_nil result.response_text
    assert_nil result.execution.ai_response_text
    assert_equal "SCHEMA_VALIDATION_ERROR", result.execution.error_category
  end

  test "rejects AI planner response missing required 'response' field" do
    missing_response_plan = @valid_plan_data.except("response")

    router = MockRouter.new(missing_response_plan)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.failure?
    assert_includes result.error_message, "Missing required field 'response'"
    assert_equal "failed", @task.reload.status
    assert_equal "failed", result.execution.status
    assert_nil result.response_text
    assert_nil result.execution.ai_response_text
  end

  test "14. records complete provider metadata on execution and audit event" do
    custom_metadata = {
      fallback_reason: "Local provider (ollama) failed: connection refused",
      retry_count: 1
    }

    mock_response = Ai::Response.new(
      raw_content: @valid_plan_data.to_json,
      data: @valid_plan_data,
      provider: "gemini",
      model: "gemini-2.5-pro",
      duration_ms: 245.5,
      fallback_used: true,
      metadata: custom_metadata
    )

    router = Object.new
    router.define_singleton_method(:generate) { |*args, **kwargs| mock_response }

    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?
    execution = result.execution

    # Direct attributes on execution
    assert_equal "gemini", execution.provider
    assert_equal "gemini", execution.provider_name
    assert_equal "gemini-2.5-pro", execution.ai_model
    assert_equal 245.5, execution.inference_duration
    assert_equal true, execution.fallback_used
    assert execution.fallback_used?
    assert_equal "Local provider (ollama) failed: connection refused", execution.fallback_reason
    assert_equal 1, execution.retry_count
    assert_equal "CLOUD FALLBACK — GEMINI", execution.provider_badge_label

    # Metadata recorded in AuditEvent
    audit = AuditEvent.where(execution: execution, event_type: "plan_generated").last
    assert_not_nil audit
    assert_equal "gemini", audit.metadata["provider"]
    assert_equal "gemini-2.5-pro", audit.metadata["model"]
    assert_equal 245.5, audit.metadata["duration_ms"]
    assert_equal true, audit.metadata["fallback_used"]
    assert_equal "Local provider (ollama) failed: connection refused", audit.metadata["fallback_reason"]
    assert_equal 1, audit.metadata["retry_count"]
  end

  test "returns nil for response_text on failed execution and never returns Plan prepared" do
    failing_router = MockRouter.new(nil, error_to_raise: Ai::TimeoutError.new("Provider timed out after 30 seconds"))
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: failing_router)

    assert result.failure?
    assert_nil result.response_text
    assert_nil result.execution.ai_response_text
    assert_not_equal "Plan prepared.", result.execution.ai_response_text
    assert_equal "PROVIDER_TIMEOUT", result.execution.error_category
  end

  test "Scenario 9: conversation mode creates zero agent steps and cannot execute tools" do
    conversation_response = {
      "mode" => "conversation",
      "response" => "I am VAISASTRAM, a governed AI agent system. I help users plan tasks while Ruby independently enforces authorization.",
      "goal" => nil,
      "steps" => []
    }

    router = MockRouter.new(conversation_response)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?
    assert_equal "conversation", result.mode
    assert result.conversation?
    refute result.action_plan?
    refute result.requires_action?

    # Verify zero steps in database and result
    assert_equal 0, result.steps.size
    assert_equal 0, result.execution.agent_steps.count
    refute result.execution.requires_action?
    assert result.execution.conversation?
    refute result.execution.action_plan?

    # Verify audit event logged as conversation_replied
    audit = AuditEvent.where(execution: result.execution, event_type: "conversation_replied").last
    assert_not_nil audit
    assert_equal "conversation", audit.metadata["mode"]
    assert_equal 0, audit.metadata["steps_count"]
    refute audit.metadata["requires_action"]
  end

  test "action_plan mode records plan_generated audit event and pending agent steps" do
    router = MockRouter.new(@valid_plan_data)
    result = Planning::AgentPlanner.plan(task: @task, user: @user, provider_router: router)

    assert result.success?
    assert_equal "action_plan", result.mode
    assert result.action_plan?
    refute result.conversation?
    assert result.requires_action?

    assert_equal 3, result.steps.size
    assert_equal 3, result.execution.agent_steps.count
    assert result.execution.requires_action?

    audit = AuditEvent.where(execution: result.execution, event_type: "plan_generated").last
    assert_not_nil audit
    assert_equal "action_plan", audit.metadata["mode"]
    assert_equal 3, audit.metadata["steps_count"]
    assert audit.metadata["requires_action"]
  end

  # =========================================================
  # General-Purpose VAISASTRAM Identity & Non-Financial Tests
  # =========================================================

  test "VAISASTRAM answers general knowledge questions in conversation mode without invoking financial tools" do
    general_task = @user.tasks.create!(
      agent: @agent,
      title: "Explain quantum computing",
      instruction: "Explain how quantum computing works at a high level.",
      submitted_at: Time.current
    )

    ai_reply = {
      "mode" => "conversation",
      "response" => "Quantum computing leverages principles of quantum mechanics, such as superposition and entanglement, to process complex information fundamentally faster than classical binary computers for specific problem classes.",
      "goal" => nil,
      "steps" => []
    }

    router = MockRouter.new(ai_reply)
    result = Planning::AgentPlanner.plan(task: general_task, user: @user, provider_router: router)

    assert result.success?
    assert_equal "conversation", result.mode
    assert result.conversation?
    assert_equal 0, result.steps.size
    assert_equal 0, result.execution.agent_steps.count
    refute result.execution.requires_action?
    assert_includes result.response_text, "Quantum computing leverages principles"
    assert_nil result.plan["goal"]

    # Verify no financial tools were invoked or scheduled
    assert_empty result.execution.agent_steps
  end

  test "VAISASTRAM introduces itself as VAISASTRAM in conversational mode" do
    identity_task = @user.tasks.create!(
      agent: @agent,
      title: "Who are you?",
      instruction: "Who are you and what do you do?",
      submitted_at: Time.current
    )

    ai_reply = {
      "mode" => "conversation",
      "response" => "I am VAISASTRAM, a general-purpose governed autonomous AI agent platform. I operate under the philosophy 'AI proposes. Ruby decides.', ensuring autonomy with accountability.",
      "goal" => nil,
      "steps" => []
    }

    router = MockRouter.new(ai_reply)
    result = Planning::AgentPlanner.plan(task: identity_task, user: @user, provider_router: router)

    assert result.success?
    assert_equal "conversation", result.mode
    assert_includes result.response_text, "I am VAISASTRAM"
    assert_includes result.response_text, "AI proposes. Ruby decides."
    assert_equal 0, result.execution.agent_steps.count
  end

  test "VAISASTRAM brainstorms technical architecture ideas in conversation mode without invoking financial tools" do
    brainstorm_task = @user.tasks.create!(
      agent: @agent,
      title: "Brainstorm architecture ideas",
      instruction: "Brainstorm architectural patterns for building an event-driven system.",
      submitted_at: Time.current
    )

    ai_reply = {
      "mode" => "conversation",
      "response" => "Here are three effective architectural patterns for event-driven systems: 1) Event Sourcing for complete state history, 2) CQRS to separate reads from writes, and 3) Outbox Pattern for reliable transactional event dispatching.",
      "goal" => nil,
      "steps" => []
    }

    router = MockRouter.new(ai_reply)
    result = Planning::AgentPlanner.plan(task: brainstorm_task, user: @user, provider_router: router)

    assert result.success?
    assert_equal "conversation", result.mode
    assert_includes result.response_text, "Event Sourcing"
    assert_equal 0, result.execution.agent_steps.count
  end
end
