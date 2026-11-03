require "test_helper"

class AiGeminiProviderTest < ActiveSupport::TestCase
  class TestableGeminiProvider < Ai::GeminiProvider
    attr_accessor :mock_response, :mock_exception

    def execute_http_request(prompt, options)
      raise @mock_exception if @mock_exception
      @mock_response
    end
  end

  setup do
    @provider = TestableGeminiProvider.new(api_key: "test-gemini-key", model: "gemini-2.5-pro", timeout: 5)
  end

  test "provider identification" do
    assert_equal "gemini", @provider.provider_name
    assert_equal "gemini-2.5-pro", @provider.model
  end

  test "raises configuration error if API key is missing" do
    provider_without_key = Ai::GeminiProvider.new(api_key: "")
    assert_raises(Ai::ConfigurationError) do
      provider_without_key.generate("Hello")
    end
  end

  test "successfully parses valid Gemini JSON response" do
    gemini_body = {
      candidates: [
        {
          content: {
            parts: [
              {
                text: { status: "success", message: "Invoice information retrieved", data: { invoice_id: "INV-100" } }.to_json
              }
            ]
          },
          finishReason: "STOP"
        }
      ],
      usageMetadata: { promptTokenCount: 25, candidatesTokenCount: 30 }
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", gemini_body)

    res = @provider.generate("Lookup invoice INV-100")
    assert_instance_of Ai::Response, res
    assert_equal "gemini", res.provider
    assert_equal "gemini-2.5-pro", res.model
    assert_equal "success", res["status"]
    assert_equal "INV-100", res.dig("data", "invoice_id")
    assert_equal 25, res.metadata.dig(:usage, "promptTokenCount")
  end

  test "maps HTTP 401/403 to AuthenticationError" do
    @provider.mock_exception = Ai::AuthenticationError.new("Invalid API key", provider: "gemini", status_code: 401)
    assert_raises(Ai::AuthenticationError) do
      @provider.generate("Test prompt")
    end
  end

  test "maps HTTP 429 to RateLimitError" do
    @provider.mock_exception = Ai::RateLimitError.new("Quota exceeded", provider: "gemini", status_code: 429)
    assert_raises(Ai::RateLimitError) do
      @provider.generate("Test prompt")
    end
  end

  test "maps HTTP 500 to ServerError" do
    @provider.mock_exception = Ai::ServerError.new("Internal Server Error", provider: "gemini", status_code: 500)
    assert_raises(Ai::ServerError) do
      @provider.generate("Test prompt")
    end
  end

  test "maps Net::OpenTimeout to TimeoutError" do
    @provider.mock_exception = Net::OpenTimeout.new("execution expired")
    assert_raises(Ai::TimeoutError) do
      @provider.generate("Test prompt")
    end
  end

  test "maps SocketError to NetworkError" do
    @provider.mock_exception = SocketError.new("getaddrinfo failed")
    assert_raises(Ai::NetworkError) do
      @provider.generate("Test prompt")
    end
  end

  test "handle_http_errors directly raises appropriate error types" do
    resp_401 = Struct.new(:code, :body).new("401", '{"error":{"message":"Bad API Key"}}')
    assert_raises(Ai::AuthenticationError) { @provider.send(:handle_http_errors!, resp_401) }

    resp_400 = Struct.new(:code, :body).new("400", '{"error":{"message":"Bad Request"}}')
    assert_raises(Ai::InvalidRequestError) { @provider.send(:handle_http_errors!, resp_400) }

    resp_404 = Struct.new(:code, :body).new("404", '{"error":{"message":"Model Not Found"}}')
    assert_raises(Ai::ModelNotFoundError) { @provider.send(:handle_http_errors!, resp_404) }

    resp_429 = Struct.new(:code, :body).new("429", '{"error":{"message":"Rate limit"}}')
    assert_raises(Ai::RateLimitError) { @provider.send(:handle_http_errors!, resp_429) }

    resp_500 = Struct.new(:code, :body).new("500", '{"error":{"message":"Internal Error"}}')
    assert_raises(Ai::ServerError) { @provider.send(:handle_http_errors!, resp_500) }
  end

  test "parses JSON wrapped in markdown fences" do
    fenced_content = "```json\n{\"goal\":\"Process invoice\",\"response\":\"Processing\",\"steps\":[]}\n```"
    gemini_body = {
      candidates: [
        {
          content: { parts: [{ text: fenced_content }] },
          finishReason: "STOP"
        }
      ]
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", gemini_body)

    res = @provider.generate("Plan task")
    assert_equal "Process invoice", res["goal"]
    assert_equal "Processing", res["response"]
  end

  test "raises ValidationError on malformed JSON" do
    gemini_body = {
      candidates: [
        {
          content: { parts: [{ text: "This is not valid JSON" }] },
          finishReason: "STOP"
        }
      ]
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", gemini_body)

    err = assert_raises(Ai::ValidationError) do
      @provider.generate("Plan task")
    end
    assert_includes err.message, "Gemini response is not valid JSON"
  end
end
