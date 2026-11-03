require "test_helper"

class WorkspaceControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @agent = agents(:financial_agent)

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
  end

  test "redirects to login when unauthenticated" do
    get workspace_url
    assert_redirected_to new_user_session_url
  end

  test "renders workspace when authenticated" do
    sign_in @user
    get workspace_url
    assert_response :success
    assert_select "h1", text: /Agent Workspace/
    assert_select "textarea#workspace-prompt"
  end

  test "submits new task instruction and renders conversational chat and separate structured plan" do
    sign_in @user

    mock_plan = {
      "response" => "I have prepared a 3-step plan to lookup invoice INV-100, verify the billing record, and prepare payment of ₹5,000.",
      "requires_action" => true,
      "goal" => "Verify invoice INV-100 and prepare payment",
      "summary" => "Retrieve, verify, and prepare payment voucher.",
      "steps" => [
        {
          "step_number" => 1,
          "action" => "lookup_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Lookup invoice record"
        },
        {
          "step_number" => 2,
          "action" => "verify_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Verify invoice record"
        },
        {
          "step_number" => 3,
          "action" => "prepare_payment",
          "arguments" => { "invoice_id" => "INV-100", "amount" => 5000 },
          "description" => "Prepare payment voucher"
        }
      ]
    }

    mock_response = Ai::Response.new(
      raw_content: mock_plan.to_json,
      data: mock_plan,
      provider: "gemini",
      model: "gemini-2.5-pro",
      duration_ms: 120.0
    )

    Ai::ProviderRouter.any_instance.stubs(:generate).returns(mock_response) if respond_to?(:stubs)

    # Use stubbing or mock router test double
    router = Object.new
    router.define_singleton_method(:generate) { |*args, **kwargs| mock_response }

    begin
      Planning::AgentPlanner.default_router_override = router
      post workspace_url, params: {
        instruction: "Verify invoice INV-100 and prepare a payment of ₹5,000"
      }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    # Agent identity is VAISASTRAM AGENT
    assert_select "span", text: "VAISASTRAM AGENT"

    # Conversational chat response is displayed in the chat interface
    assert_select "p", text: /I have prepared a 3-step plan to lookup invoice INV-100/

    # Structured plan is displayed separately
    assert_select "h2", text: /Structured Execution Plan/
    assert_select "span", text: /PROPOSED \(UNEXECUTED\)/
    assert_select "span", text: /lookup_invoice/
    assert_select "span", text: /verify_invoice/
    assert_select "span", text: /prepare_payment/

    # Arguments are rendered cleanly without raw JSON
    assert_select "span", text: /invoice_id:/
    assert_select "span", text: /INV-100/
    assert_select "span", text: /amount:/

    # Asserts prospective language assurance
    assert_select "span", text: /Actions are proposed only\. Zero tools have been executed\./
  end

  test "displays clarifying questions when essential information is missing" do
    sign_in @user

    mock_clarification = {
      "response" => "Could you please specify which invoice ID you want to verify?",
      "requires_action" => false,
      "goal" => "Clarification needed",
      "summary" => "Missing invoice identifier",
      "steps" => [],
      "clarification_needed" => "Invoice ID is missing from your instruction."
    }

    mock_response = Ai::Response.new(
      raw_content: mock_clarification.to_json,
      data: mock_clarification,
      provider: "gemini",
      model: "gemini-2.5-pro",
      duration_ms: 90.0
    )

    router = Object.new
    router.define_singleton_method(:generate) { |*args, **kwargs| mock_response }

    begin
      Planning::AgentPlanner.default_router_override = router
      post workspace_url, params: {
        instruction: "Please verify the invoice"
      }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    # Shows human-readable question
    assert_select "p", text: /Could you please specify which invoice ID you want to verify\?/
    # Shows clarification box
    assert_select "div", text: /Invoice ID is missing from your instruction\./
    # In conversation mode, no execution plan card is rendered and zero tools are executed
    assert_select "h2", { count: 0, text: /Structured Execution Plan/ }
    assert_select "span", text: /Conversational inquiry\. No tool actions required\./
  end

  test "displays explanation when requested action cannot be planned" do
    sign_in @user

    mock_unplannable = {
      "response" => "I cannot execute arbitrary shell commands to wipe system logs, as this is outside permit-listed capabilities.",
      "requires_action" => false,
      "goal" => "Unplannable request",
      "summary" => "Requested action is outside allowlisted capabilities.",
      "steps" => [],
      "explanation" => "Prohibited action key: shell execution is strictly disallowed."
    }

    mock_response = Ai::Response.new(
      raw_content: mock_unplannable.to_json,
      data: mock_unplannable,
      provider: "gemini",
      model: "gemini-2.5-pro",
      duration_ms: 80.0
    )

    router = Object.new
    router.define_singleton_method(:generate) { |*args, **kwargs| mock_response }

    begin
      Planning::AgentPlanner.default_router_override = router
      post workspace_url, params: {
        instruction: "Wipe all system logs with rm -rf"
      }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    # Shows human-readable explanation
    assert_select "p", text: /I cannot execute arbitrary shell commands to wipe system logs/
    # Shows unplannable explanation callout
    assert_select "div", text: /Prohibited action key: shell execution is strictly disallowed\./
    # In conversation mode, no execution plan card is rendered
    assert_select "h2", { count: 0, text: /Structured Execution Plan/ }
    assert_select "span", text: /Conversational inquiry\. No tool actions required\./
  end

  test "renders failed planning state in UI with error category and zero actions on provider failure" do
    sign_in @user

    failing_router = Object.new
    failing_router.define_singleton_method(:generate) do |*args, **kwargs|
      raise Ai::TimeoutError.new("Request to gemini timed out after 30s: execution expired", provider: "gemini")
    end

    begin
      Planning::AgentPlanner.default_router_override = failing_router
      post workspace_url, params: {
        instruction: "Pay invoice INV-999 immediately"
      }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    # Shows "Planning failed"
    assert_select "span", text: /Planning failed/

    # Shows error category for debugging
    assert_select "span", text: /PROVIDER_TIMEOUT/

    # Shows detailed error message
    assert_select "div", text: /Request to gemini timed out after 30s/

    # Execution plan section shows failed state with 0 actions planned
    assert_select "span", text: /0 actions planned on failure/
    assert_select "span", text: "FAILED"

    # CRITICAL: Must NOT render false success message or false planned badge
    assert_select "p", { text: /Plan prepared\./, count: 0 }, "Must never display 'Plan prepared.' on failure"
    assert_select "span", { text: /PROPOSED \(UNEXECUTED\)/, count: 0 }, "Must not display proposed badge on failure"
  end

  test "renders failed planning state when both providers fail without false success" do
    sign_in @user

    all_failed_router = Object.new
    all_failed_router.define_singleton_method(:generate) do |*args, **kwargs|
      raise Ai::AllProvidersFailedError.new("All AI providers failed. Primary (gemini): connection timed out; Fallback (groq): rate limit exceeded")
    end

    begin
      Planning::AgentPlanner.default_router_override = all_failed_router
      post workspace_url, params: {
        instruction: "Reconcile vendor accounts"
      }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    assert_select "span", text: /Planning failed/
    assert_select "span", text: /ALL_PROVIDERS_FAILED/
    assert_select "div", text: /All AI providers failed/
    assert_select "span", text: /0 actions planned on failure/

    # Absolutely no false success strings
    assert_select "p", { text: /Plan prepared\./, count: 0 }
    assert_select "span", { text: /PROPOSED \(UNEXECUTED\)/, count: 0 }
  end

  # =========================================================
  # Scenario 10: Hotwire UI rendering for conversation vs action_plan
  # =========================================================

  test "Scenario 10: Hotwire UI renders conversation mode without execution plan card and action_plan with execution plan card" do
    sign_in @user

    # 1. Test Conversation Mode
    conv_data = {
      "mode" => "conversation",
      "response" => "I am VAISASTRAM, a governed autonomous AI agent platform. How may I assist you?",
      "goal" => nil,
      "steps" => []
    }
    conv_response = Ai::Response.new(
      raw_content: conv_data.to_json,
      data: conv_data,
      provider: "gemini",
      model: "gemini-2.5-pro",
      duration_ms: 50.0
    )

    router = Object.new
    router.define_singleton_method(:generate) { |*args, **kwargs| conv_response }

    begin
      Planning::AgentPlanner.default_router_override = router
      post workspace_url, params: { instruction: "Who are you?" }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    # Conversation UI assertions:
    # 1. Displays natural-language answer
    assert_select "p", text: /I am VAISASTRAM, a governed autonomous AI agent platform\./
    # 2. Displays model and provider badge
    assert_select "span", text: /CLOUD AI — GEMINI/
    assert_select "span", text: /gemini-2.5-pro/
    # 3. Does not display failed planning status
    assert_select "span", { text: /Planning failed/, count: 0 }
    # 4. Does not display execution plan card
    assert_select "h2", { text: /Structured Execution Plan/, count: 0 }
    assert_select "span", text: /Conversational inquiry\. No tool actions required\./

    # 2. Test Action Plan Mode
    act_data = {
      "mode" => "action_plan",
      "response" => "I will verify invoice INV-100 before processing.",
      "goal" => "Verify invoice INV-100",
      "steps" => [
        {
          "step_number" => 1,
          "action" => "lookup_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Lookup invoice record"
        }
      ]
    }
    act_response = Ai::Response.new(
      raw_content: act_data.to_json,
      data: act_data,
      provider: "gemini",
      model: "gemini-2.5-pro",
      duration_ms: 100.0
    )

    act_router = Object.new
    act_router.define_singleton_method(:generate) { |*args, **kwargs| act_response }

    begin
      Planning::AgentPlanner.default_router_override = act_router
      post workspace_url, params: { instruction: "Verify invoice INV-100" }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    # Action Plan UI assertions:
    # 1. Displays natural-language explanation
    assert_select "p", text: /I will verify invoice INV-100 before processing\./
    # 2. Displays structured execution plan card
    assert_select "h2", text: /Structured Execution Plan/
    # 3. Displays PROPOSED (UNEXECUTED) badge
    assert_select "span", text: /PROPOSED \(UNEXECUTED\)/
    assert_select "span", text: /lookup_invoice/
  end

  test "renders VAISASTRAM AGENT identity and answers general questions without invoking financial tools in Hotwire UI" do
    sign_in @user

    general_answer = {
      "mode" => "conversation",
      "response" => "The CAP theorem states that any distributed data store can only guarantee at most two of the following three properties simultaneously: Consistency, Availability, and Partition tolerance.",
      "goal" => nil,
      "steps" => []
    }

    mock_response = Ai::Response.new(
      raw_content: general_answer.to_json,
      data: general_answer,
      provider: "ollama",
      model: "gemma3:4b",
      duration_ms: 60.0
    )

    router = Object.new
    router.define_singleton_method(:generate) { |*args, **kwargs| mock_response }

    begin
      Planning::AgentPlanner.default_router_override = router
      post workspace_url, params: { instruction: "Explain the CAP theorem" }
    ensure
      Planning::AgentPlanner.default_router_override = nil
    end

    assert_redirected_to(/workspace\?task_id=\d+/)
    follow_redirect!
    assert_response :success

    # Verifies the agent identity header renders "VAISASTRAM AGENT" (and NOT "FINANCIAL OPERATIONS AGENT")
    assert_select "span", text: "VAISASTRAM AGENT"
    assert_select "span", { text: /FINANCIAL OPERATIONS AGENT/, count: 0 }

    # Verifies conversational answer is rendered
    assert_select "p", text: /The CAP theorem states that any distributed data store/

    # Verifies local inference badge
    assert_select "span", text: /LOCAL AI — GEMMA3:4B/

    # Verifies assurance indicator for conversation without tool actions
    assert_select "span", text: /Conversational inquiry\. No tool actions required\./

    # Verifies NO execution plan card and NO financial tools proposed in active session
    assert_select "h2", { text: /Structured Execution Plan/, count: 0 }
    assert_select "span", { text: /PROPOSED \(UNEXECUTED\)/, count: 0 }

    created_task = @user.tasks.order(created_at: :desc).first
    active_exec = created_task.executions.order(created_at: :desc).first
    assert_not_nil active_exec
    assert_empty active_exec.agent_steps
    assert_equal 0, active_exec.agent_steps.count
    assert active_exec.conversation?
    refute active_exec.requires_action?
  end
end
