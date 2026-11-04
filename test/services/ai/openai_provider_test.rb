require "test_helper"

class AiOpenaiProviderTest < ActiveSupport::TestCase
  class TestableOpenaiProvider < Ai::OpenaiProvider
    attr_accessor :mock_response, :mock_exception

    def execute_http_request(prompt, options)
      raise @mock_exception if @mock_exception
      @mock_response
    end
  end

  setup do
    @provider = TestableOpenaiProvider.new(api_key: "test-openai-key", model: "gpt-4o", timeout: 5)
  end

  test "provider identification" do
    assert_equal "openai", @provider.provider_name
    assert_equal "gpt-4o", @provider.model
  end

  test "raises configuration error if API key is missing" do
    provider_without_key = Ai::OpenaiProvider.new(api_key: "")
    assert_raises(Ai::ConfigurationError) do
      provider_without_key.generate("Hello")
    end
  end

  test "successfully parses valid OpenAI JSON response" do
    openai_body = {
      choices: [
        {
          message: {
            role: "assistant",
            content: { status: "success", message: "Processed via OpenAI GPT", data: { invoice_id: "INV-100" } }.to_json
          },
          finish_reason: "stop"
        }
      ],
      usage: { prompt_tokens: 50, completion_tokens: 45 }
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", openai_body)

    res = @provider.generate("Lookup invoice INV-100")
    assert_instance_of Ai::Response, res
    assert_equal "openai", res.provider
    assert_equal "gpt-4o", res.model
    assert_equal "success", res["status"]
    assert_equal "INV-100", res.dig("data", "invoice_id")
    assert_equal 50, res.metadata.dig(:usage, "prompt_tokens")
  end

  test "extracts JSON from Markdown code blocks" do
    fenced_content = "```json\n{\"plan\": \"valid\", \"invoice_id\": \"INV-100\"}\n```"
    openai_body = {
      choices: [
        {
          message: { role: "assistant", content: fenced_content },
          finish_reason: "stop"
        }
      ]
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", openai_body)

    res = @provider.generate("Test prompt")
    assert_equal "valid", res["plan"]
    assert_equal "INV-100", res["invoice_id"]
  end

  test "maps HTTP 401 to AuthenticationError" do
    @provider.mock_exception = Ai::AuthenticationError.new("Invalid API Key", provider: "openai", status_code: 401)
    assert_raises(Ai::AuthenticationError) do
      @provider.generate("Test prompt")
    end
  end
end
