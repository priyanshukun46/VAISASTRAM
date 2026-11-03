require "test_helper"

class PlanValidatorTest < ActiveSupport::TestCase
  setup do
    @allowed_tools = %w[lookup_invoice verify_invoice prepare_payment]
    @valid_plan = {
      "goal" => "Verify invoice INV-100 and prepare payment",
      "response" => "I will verify invoice INV-100 and prepare a payment voucher for approval.",
      "summary" => "Retrieve and verify the invoice before preparing payment.",
      "steps" => [
        {
          "step_number" => 1,
          "action" => "lookup_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Retrieve invoice details."
        },
        {
          "step_number" => 2,
          "action" => "verify_invoice",
          "arguments" => { "invoice_id" => "INV-100" },
          "description" => "Verify invoice information."
        },
        {
          "step_number" => 3,
          "action" => "prepare_payment",
          "arguments" => { "invoice_id" => "INV-100", "amount" => 5000, "currency" => "INR" },
          "description" => "Prepare the requested payment."
        }
      ]
    }
  end

  test "accepts valid multiple-step plan" do
    assert Planning::PlanValidator.validate!(@valid_plan, allowed_tools: @allowed_tools)
  end

  test "rejects missing required top-level fields" do
    %w[goal response steps].each do |field|
      invalid = @valid_plan.except(field)
      err = assert_raises(Planning::ValidationError) do
        Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
      end
      assert_includes err.message, "Missing required field '#{field}'"
    end
  end

  test "rejects unexpected top-level fields" do
    invalid = @valid_plan.merge("unauthorized_field" => "malicious")
    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "Unexpected top-level fields"
  end

  test "rejects empty plan (no steps)" do
    invalid = @valid_plan.merge("steps" => [])
    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "Plan must contain at least one step"
  end

  test "rejects plan exceeding 10 steps" do
    eleven_steps = (1..11).map do |i|
      {
        "step_number" => i,
        "action" => "lookup_invoice",
        "arguments" => { "invoice_id" => "INV-#{i}" },
        "description" => "Step #{i}"
      }
    end

    invalid = @valid_plan.merge("steps" => eleven_steps)
    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "Plan exceeds maximum allowed steps"
  end

  test "rejects duplicate step numbers" do
    invalid = @valid_plan.deep_dup
    invalid["steps"][1]["step_number"] = 1 # Duplicate step number 1

    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "Step number mismatch: expected 2, got 1"
  end

  test "rejects non-sequential step numbers" do
    invalid = @valid_plan.deep_dup
    invalid["steps"][1]["step_number"] = 3 # Skips step 2

    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "Step number mismatch: expected 2, got 3"
  end

  test "rejects unexpected or disallowed action names" do
    invalid = @valid_plan.deep_dup
    invalid["steps"][0]["action"] = "unregistered_external_api"

    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "unknown or disallowed action"
  end

  test "rejects invalid argument types (e.g. array or primitive instead of object)" do
    invalid = @valid_plan.deep_dup
    invalid["steps"][0]["arguments"] = ["INV-100"] # Array instead of Hash

    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "arguments must be a JSON object"
  end

  test "rejects step with malicious argument keys" do
    invalid = @valid_plan.deep_dup
    invalid["steps"][0]["arguments"] = { "__exec__" => "touch /tmp/pwned" }

    err = assert_raises(Planning::ValidationError) do
      Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
    end
    assert_includes err.message, "Malicious argument key detected"
  end

  test "accepts conversational plan with clarification needed and no steps" do
    clarification_plan = {
      "response" => "Could you please specify the invoice ID and vendor name you would like me to verify?",
      "requires_action" => false,
      "goal" => "Clarification needed for invoice verification",
      "summary" => "Missing invoice ID and vendor name.",
      "steps" => [],
      "clarification_needed" => "Invoice ID and vendor name are missing."
    }

    assert Planning::PlanValidator.validate!(clarification_plan, allowed_tools: @allowed_tools)
  end

  test "accepts conversational plan with explanation for unplannable request" do
    unplannable_plan = {
      "response" => "I cannot delete database records or execute shell scripts as these actions are not permitted.",
      "requires_action" => false,
      "goal" => "Unplannable request",
      "summary" => "Requested actions are outside allowlisted tools.",
      "steps" => [],
      "explanation" => "Prohibited database or shell mutation."
    }

    assert Planning::PlanValidator.validate!(unplannable_plan, allowed_tools: @allowed_tools)
  end

  test "rejects AI response that falsely implies an action has already been executed" do
    forbidden_plans = [
      "I have executed the payment of ₹5,000 for invoice INV-100.",
      "We have completed the invoice lookup and disbursed funds.",
      "The payment was completed and transfer sent.",
      "Actions were executed successfully."
    ]

    forbidden_plans.each do |response_text|
      invalid = @valid_plan.merge("response" => response_text)
      err = assert_raises(Planning::ValidationError) do
        Planning::PlanValidator.validate!(invalid, allowed_tools: @allowed_tools)
      end
      assert_includes err.message, "falsely implies actions have already been executed"
    end
  end
end
