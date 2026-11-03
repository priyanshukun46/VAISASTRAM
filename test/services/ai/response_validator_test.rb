require "test_helper"

class AiResponseValidatorTest < ActiveSupport::TestCase
  test "validates valid generic structured response" do
    valid_payload = {
      "status" => "success",
      "message" => "Invoice information retrieved",
      "data" => {
        "invoice_id" => "INV-100"
      }
    }

    result = Ai::ResponseValidator.validate!(valid_payload)
    assert_equal "success", result["status"]
    assert_equal "INV-100", result.dig("data", "invoice_id")
  end

  test "parses and validates JSON string directly" do
    json_string = '{"status": "success", "message": "Ready", "data": {"key": "val"}}'
    result = Ai::ResponseValidator.validate!(json_string)
    assert_equal "success", result["status"]
  end

  test "handles markdown fenced JSON code blocks gracefully" do
    fenced_json = "```json\n{\"status\": \"success\", \"message\": \"Fenced\", \"data\": {}}\n```"
    result = Ai::ResponseValidator.validate!(fenced_json)
    assert_equal "success", result["status"]
  end

  test "rejects malformed JSON" do
    malformed = '{"status": "success", invalid json here'
    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!(malformed)
    end
  end

  test "rejects empty or whitespace response" do
    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!("   ")
    end
  end

  test "rejects responses exceeding size limits" do
    huge_string = "a" * (Ai::ResponseValidator::MAX_RESPONSE_BYTESIZE + 10)
    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!(huge_string)
    end
  end

  test "rejects missing required status field" do
    missing_status = { "message" => "No status here", "data" => {} }
    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!(missing_status)
    end
  end

  test "rejects invalid status value" do
    invalid_status = { "status" => "unsupported_status", "data" => {} }
    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!(invalid_status)
    end
  end

  test "validates against custom schema requirements and types" do
    schema = {
      required: [:invoice_id, :amount],
      types: {
        invoice_id: String,
        amount: [Integer, Float]
      }
    }

    valid_data = { "invoice_id" => "INV-100", "amount" => 5000 }
    assert_nothing_raised do
      Ai::ResponseValidator.validate!(valid_data, schema)
    end

    missing_field = { "invoice_id" => "INV-100" }
    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!(missing_field, schema)
    end

    wrong_type = { "invoice_id" => "INV-100", "amount" => "five thousand" }
    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!(wrong_type, schema)
    end
  end

  test "detects and rejects potentially malicious execution injection keys" do
    suspicious = {
      "status" => "success",
      "data" => {
        "__exec__" => "rm -rf /"
      }
    }

    assert_raises(Ai::ValidationError) do
      Ai::ResponseValidator.validate!(suspicious)
    end
  end
end
