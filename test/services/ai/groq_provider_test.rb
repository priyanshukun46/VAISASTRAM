require "test_helper"

class AiGroqProviderTest < ActiveSupport::TestCase
  class TestableGroqProvider < Ai::GroqProvider
    attr_accessor :mock_response, :mock_exception

    def execute_http_request(prompt, options)
      raise @mock_exception if @mock_exception
      @mock_response
    end
  end

  setup do
    @provider = TestableGroqProvider.new(api_key: "test-groq-key", model: "llama-3.3-70b-versatile", timeout: 5)
  end

  test "provider identification" do
    assert_equal "groq", @provider.provider_name
    assert_equal "llama-3.3-70b-versatile", @provider.model
  end

  test "raises configuration error if API key is missing" do
    provider_without_key = Ai::GroqProvider.new(api_key: "")
    assert_raises(Ai::ConfigurationError) do
      provider_without_key.generate("Hello")
    end
  end

  test "successfully parses valid Groq JSON response" do
    groq_body = {
      choices: [
        {
          message: {
            role: "assistant",
            content: { status: "success", message: "Invoice processed via Groq fallback", data: { invoice_id: "INV-100" } }.to_json
          },
          finish_reason: "stop"
        }
      ],
      usage: { prompt_tokens: 40, completion_tokens: 35 }
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", groq_body)

    res = @provider.generate("Lookup invoice INV-100")
    assert_instance_of Ai::Response, res
    assert_equal "groq", res.provider
    assert_equal "llama-3.3-70b-versatile", res.model
    assert_equal "success", res["status"]
    assert_equal "INV-100", res.dig("data", "invoice_id")
    assert_equal 40, res.metadata.dig(:usage, "prompt_tokens")
  end

  test "maps HTTP 401 to AuthenticationError" do
    @provider.mock_exception = Ai::AuthenticationError.new("Invalid API Key", provider: "groq", status_code: 401)
    assert_raises(Ai::AuthenticationError) do
      @provider.generate("Test prompt")
    end
  end

  test "maps HTTP 429 to RateLimitError" do
    @provider.mock_exception = Ai::RateLimitError.new("Rate limit reached", provider: "groq", status_code: 429)
    assert_raises(Ai::RateLimitError) do
      @provider.generate("Test prompt")
    end
  end

  test "maps HTTP 503 to ServerError" do
    @provider.mock_exception = Ai::ServerError.new("Groq Service Unavailable", provider: "groq", status_code: 503)
    assert_raises(Ai::ServerError) do
      @provider.generate("Test prompt")
    end
  end

  test "parses valid structured response matching unified contract" do
    plan_body = {
      goal: "Prepare payment for vendor invoice.",
      response: "I will verify the invoice and prepare a payment request for approval.",
      steps: [
        {
          step_number: 1,
          action: "retrieve_invoice",
          arguments: { invoice_id: "INV-100" },
          description: "Retrieve the invoice."
        }
      ]
    }

    groq_body = {
      choices: [
        {
          message: { role: "assistant", content: plan_body.to_json },
          finish_reason: "stop"
        }
      ],
      usage: { prompt_tokens: 30, completion_tokens: 45 }
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", groq_body)

    res = @provider.generate("Process INV-100")
    assert_equal "Prepare payment for vendor invoice.", res["goal"]
    assert_equal "I will verify the invoice and prepare a payment request for approval.", res["response"]
    assert_equal 1, res["steps"].size
    assert_equal "retrieve_invoice", res["steps"][0]["action"]
  end

  test "parses JSON wrapped in markdown code fences" do
    fenced_content = "```json\n{\"goal\":\"Prepare payment\",\"response\":\"Will prepare\",\"steps\":[]}\n```"
    groq_body = {
      choices: [
        {
          message: { role: "assistant", content: fenced_content },
          finish_reason: "stop"
        }
      ]
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", groq_body)

    res = @provider.generate("Plan payment")
    assert_equal "Prepare payment", res["goal"]
    assert_equal "Will prepare", res["response"]
  end

  test "raises ValidationError on malformed JSON from Groq" do
    groq_body = {
      choices: [
        {
          message: { role: "assistant", content: "Malformed JSON response {{{{" },
          finish_reason: "stop"
        }
      ]
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", groq_body)

    err = assert_raises(Ai::ValidationError) do
      @provider.generate("Plan payment")
    end
    assert_includes err.message, "Groq response is not valid JSON"
  end

  test "raises ValidationError when Groq response is not a JSON object" do
    groq_body = {
      choices: [
        {
          message: { role: "assistant", content: "[1, 2, 3]" },
          finish_reason: "stop"
        }
      ]
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", groq_body)

    err = assert_raises(Ai::ValidationError) do
      @provider.generate("Plan payment")
    end
    assert_includes err.message, "Groq response must be a JSON object"
  end
end
