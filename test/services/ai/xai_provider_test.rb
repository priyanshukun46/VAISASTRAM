require "test_helper"

class AiXaiProviderTest < ActiveSupport::TestCase
  class TestableXaiProvider < Ai::XaiProvider
    attr_accessor :mock_response, :mock_exception

    def execute_http_request(prompt, options)
      raise @mock_exception if @mock_exception
      @mock_response
    end
  end

  setup do
    @provider = TestableXaiProvider.new(api_key: "test-xai-key", model: "grok-2-latest", timeout: 5)
  end

  test "provider identification" do
    assert_equal "grok", @provider.provider_name
    assert_equal "grok-2-latest", @provider.model
  end

  test "raises configuration error if API key is missing" do
    provider_without_key = Ai::XaiProvider.new(api_key: "")
    assert_raises(Ai::ConfigurationError) do
      provider_without_key.generate("Hello")
    end
  end

  test "successfully parses valid xAI Grok JSON response" do
    grok_body = {
      choices: [
        {
          message: {
            role: "assistant",
            content: { status: "success", message: "Processed via xAI Grok", data: { voucher_id: "VCH-GROK" } }.to_json
          },
          finish_reason: "stop"
        }
      ],
      usage: { prompt_tokens: 45, completion_tokens: 30 }
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", grok_body)

    res = @provider.generate("Generate payment voucher")
    assert_instance_of Ai::Response, res
    assert_equal "grok", res.provider
    assert_equal "grok-2-latest", res.model
    assert_equal "success", res["status"]
    assert_equal "VCH-GROK", res.dig("data", "voucher_id")
  end

  test "GrokProvider alias exists and behaves identically" do
    assert_equal Ai::XaiProvider, Ai::GrokProvider
  end
end
