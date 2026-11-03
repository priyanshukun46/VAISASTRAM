require "test_helper"

class PlanNormalizerTest < ActiveSupport::TestCase
  setup do
    @action_plan_data = {
      "mode" => "action_plan",
      "goal" => "Verify invoice INV-100 and prepare payment",
      "response" => "I will verify invoice INV-100 and prepare a payment voucher for approval.",
      "summary" => "Retrieve, verify, and prepare payment voucher.",
      "steps" => [
        {
          "step_number" => 1,
          "action" => "lookup_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Lookup invoice"
        }
      ]
    }

    @conversation_plan_data = {
      "mode" => "conversation",
      "response" => "I am VAISASTRAM, a general-purpose governed AI agent platform.",
      "goal" => nil,
      "steps" => []
    }
  end

  test "normalizes canonical conversation mode" do
    result = Planning::PlanNormalizer.normalize(@conversation_plan_data)
    assert_equal "conversation", result["mode"]
    assert_equal false, result["requires_action"]
    assert_empty result["steps"]
    assert_equal @conversation_plan_data["response"], result["response"]
  end

  test "normalizes canonical action_plan mode" do
    result = Planning::PlanNormalizer.normalize(@action_plan_data)
    assert_equal "action_plan", result["mode"]
    assert_equal true, result["requires_action"]
    assert_equal 1, result["steps"].size
    assert_equal "lookup_invoice", result["steps"][0]["action"]
    assert_equal({ "invoice_id" => "INV-100" }, result["steps"][0]["arguments"])
  end

  test "normalizes case variations in mode" do
    %w[Conversation CONVERSATION conversation].each do |variant|
      data = @conversation_plan_data.merge("mode" => variant)
      result = Planning::PlanNormalizer.normalize(data)
      assert_equal "conversation", result["mode"]
    end

    ["Action_Plan", "ACTION_PLAN", "action-plan", "Action Plan"].each do |variant|
      data = @action_plan_data.merge("mode" => variant)
      result = Planning::PlanNormalizer.normalize(data)
      assert_equal "action_plan", result["mode"]
    end
  end

  test "normalizes valid LLM model aliases to canonical modes" do
    %w[chat conversational dialogue inquiry general message].each do |alias_name|
      data = @conversation_plan_data.merge("mode" => alias_name)
      result = Planning::PlanNormalizer.normalize(data)
      assert_equal "conversation", result["mode"], "Expected alias '#{alias_name}' to normalize to conversation"
    end

    %w[actions action plan tools].each do |alias_name|
      data = @action_plan_data.merge("mode" => alias_name)
      result = Planning::PlanNormalizer.normalize(data)
      assert_equal "action_plan", result["mode"], "Expected alias '#{alias_name}' to normalize to action_plan"
    end
  end

  test "preserves invalid mode without silently inventing a valid mode" do
    invalid_data = @action_plan_data.merge("mode" => "invalid_override_mode")
    result = Planning::PlanNormalizer.normalize(invalid_data)
    assert_equal "invalid_override_mode", result["mode"]
  end

  test "infers documented safe default conversation mode when mode is omitted and steps is empty" do
    data = @conversation_plan_data.except("mode")
    result = Planning::PlanNormalizer.normalize(data)
    assert_equal "conversation", result["mode"]
    assert_equal false, result["requires_action"]
  end

  test "infers documented safe default action_plan mode when mode is omitted and valid steps and goal exist" do
    data = @action_plan_data.except("mode")
    result = Planning::PlanNormalizer.normalize(data)
    assert_equal "action_plan", result["mode"]
    assert_equal true, result["requires_action"]
    assert_equal 1, result["steps"].size
  end

  test "does not invent a mode when mode is omitted and response is ambiguous" do
    ambiguous = { "steps" => [] }
    result = Planning::PlanNormalizer.normalize(ambiguous)
    # Mode should be conversation since steps is empty array without goal
    assert_equal "conversation", result["mode"]

    completely_empty = {}
    result_empty = Planning::PlanNormalizer.normalize(completely_empty)
    assert_nil result_empty["mode"], "Completely empty payload should not have an invented mode"
  end

  test "normalizes step argument keys to strings" do
    data = @action_plan_data.deep_dup
    data["steps"][0]["arguments"] = { invoice_id: "INV-200", amount: 1500 }
    result = Planning::PlanNormalizer.normalize(data)
    assert_equal({ "invoice_id" => "INV-200", "amount" => 1500 }, result["steps"][0]["arguments"])
  end

  test "returns empty hash when input is not a hash" do
    assert_equal({}, Planning::PlanNormalizer.normalize(nil))
    assert_equal({}, Planning::PlanNormalizer.normalize("not a hash"))
    assert_equal({}, Planning::PlanNormalizer.normalize([1, 2, 3]))
  end
end
