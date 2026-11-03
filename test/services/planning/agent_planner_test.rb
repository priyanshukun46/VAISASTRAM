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
      "goal" => "Verify invoice INV-100 and prepare payment",
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
end
