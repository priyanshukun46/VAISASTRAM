require "test_helper"

class PlanningPromptTest < ActiveSupport::TestCase
  setup do
    @agent = agents(:financial_agent) # Now VAISASTRAM Agent fixture
    @tools = [
      Tool.find_or_create_by!(key: "lookup_invoice") do |t|
        t.name = "Lookup Invoice"
        t.risk_level = "low"
        t.enabled = true
      end,
      Tool.find_or_create_by!(key: "verify_invoice") do |t|
        t.name = "Verify Invoice"
        t.risk_level = "low"
        t.enabled = true
      end,
      Tool.find_or_create_by!(key: "prepare_payment") do |t|
        t.name = "Prepare Payment"
        t.risk_level = "high"
        t.enabled = true
      end
    ]
  end

  test "system prompt defines identity as VAISASTRAM and establishes general-purpose scope" do
    prompt = Planning::PlanningPrompt.build_system_prompt(agent: @agent, tools: @tools)

    # Introduces as VAISASTRAM
    assert_includes prompt, "You are VAISASTRAM, a general-purpose governed autonomous AI agent platform"
    assert_includes prompt, "Core Philosophy: \"AI proposes. Ruby decides.\""

    # General-purpose capabilities (not restricted to financial ops)
    assert_includes prompt, "NOT restricted to financial operations"
    assert_includes prompt, "answer general questions, explain technical and scientific concepts, brainstorm ideas"
    assert_includes prompt, "Financial operations (such as invoice verification and payment preparation) are simply one available domain"

    # Tool registry allowlisting & anti-invention mandates
    assert_includes prompt, "MUST NOT invent tool capabilities"
    assert_includes prompt, "ALLOWLISTED DOMAIN TOOLS:"
    assert_includes prompt, "lookup_invoice"
    assert_includes prompt, "verify_invoice"
    assert_includes prompt, "prepare_payment"

    # Both modes supported
    assert_includes prompt, '"conversation"'
    assert_includes prompt, '"action_plan"'
  end

  test "user prompt hints conversational mode without invoking financial tools for general questions" do
    general_task = Task.new(
      agent: @agent,
      instruction: "Explain how distributed consensus works in modern database systems."
    )

    prompt = Planning::PlanningPrompt.build_user_prompt(task: general_task)

    assert_includes prompt, "CLASSIFIED INTENT HINT: conversation"
    assert_includes prompt, 'Return "mode": "conversation"'
    assert_includes prompt, "Do not invoke financial tools."
  end

  test "user prompt hints action_plan mode for domain financial instructions" do
    action_task = Task.new(
      agent: @agent,
      instruction: "Verify invoice INV-100 and prepare a payment of ₹5,000"
    )

    prompt = Planning::PlanningPrompt.build_user_prompt(task: action_task)

    assert_includes prompt, "CLASSIFIED INTENT HINT: action_plan"
    assert_includes prompt, 'Return "mode": "action_plan"'
  end
end
