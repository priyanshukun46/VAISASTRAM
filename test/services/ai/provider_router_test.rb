require "test_helper"

class AiProviderRouterTest < ActiveSupport::TestCase
  class MockProvider
    attr_reader :provider_name, :model, :calls

    def initialize(name, model: "mock-model")
      @provider_name = name
      @model = model
      @calls = 0
    end

    def generate(prompt, options = {})
      @calls += 1
      Ai::Response.new(
        raw_content: { status: "success", message: "Mock response from #{@provider_name}", data: { ok: true } }.to_json,
        data: { "status" => "success", "message" => "Mock response from #{@provider_name}", "data" => { "ok" => true } },
        provider: @provider_name,
        model: @model,
        duration_ms: 120.0
      )
    end
  end

  class FailingProvider
    attr_reader :provider_name, :model, :calls, :error_to_raise

    def initialize(name, error_to_raise)
      @provider_name = name
      @model = "#{name}-model"
      @error_to_raise = error_to_raise
      @calls = 0
    end

    def generate(_prompt, _options = {})
      @calls += 1
      raise @error_to_raise
    end
  end

  test "returns primary response when primary succeeds without invoking fallback" do
    primary = MockProvider.new("gemini")
    fallback = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(primary_provider: primary, fallback_provider: fallback)
    response = router.generate("Test prompt")

    assert_equal 1, primary.calls
    assert_equal 0, fallback.calls
    assert_equal "gemini", response.provider
    assert_not response.fallback?
    assert_equal 1, router.attempts.size
    assert_equal :success, router.attempts.first[:status]
  end

  test "falls back to secondary provider when primary encounters a transient error (e.g. 429 rate limit)" do
    transient_error = Ai::RateLimitError.new("Rate limit exceeded", provider: "gemini", status_code: 429)
    primary = FailingProvider.new("gemini", transient_error)
    fallback = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(primary_provider: primary, fallback_provider: fallback)
    response = router.generate("Test prompt")

    assert_equal 2, primary.calls # 1 initial + 1 bounded retry
    assert_equal 1, fallback.calls
    assert_equal "groq", response.provider
    assert response.fallback?

    # Verify audit of attempts
    assert_equal 3, router.attempts.size # 2 primary attempts + 1 fallback
    assert_equal :failed, router.attempts[0][:status]
    assert_equal "gemini", router.attempts[0][:provider]
    assert_equal "Ai::Errors::RateLimitError", router.attempts[0][:error_class]

    assert_equal :failed, router.attempts[1][:status]
    assert_equal "gemini", router.attempts[1][:provider]

    assert_equal :success, router.attempts[2][:status]
    assert_equal "groq", router.attempts[2][:provider]
  end

  test "Gemini timeout triggers bounded retry then falls back to Groq successfully" do
    timeout_err = Ai::TimeoutError.new("Gemini timed out after 30s", provider: "gemini")
    primary = FailingProvider.new("gemini", timeout_err)
    fallback = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(primary_provider: primary, fallback_provider: fallback)
    response = router.generate("Test prompt", system_instruction: "Gov rules", schema: { required: ["status"] })

    assert_equal 2, primary.calls # 1 initial attempt + 1 bounded retry
    assert_equal 1, fallback.calls
    assert_equal "groq", response.provider
    assert response.fallback?
    assert_equal 3, router.attempts.size
    assert_equal :failed, router.attempts[0][:status]
    assert_equal :failed, router.attempts[1][:status]
    assert_equal :success, router.attempts[2][:status]
  end

  test "does NOT fallback on fatal authentication error (fails fast)" do
    auth_err = Ai::AuthenticationError.new("Invalid API Key", provider: "gemini", status_code: 401)
    primary = FailingProvider.new("gemini", auth_err)
    fallback = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(primary_provider: primary, fallback_provider: fallback)

    assert_raises(Ai::AuthenticationError) do
      router.generate("Test prompt")
    end

    # Fallback must NEVER have been called for invalid key
    assert_equal 0, fallback.calls
  end

  test "does NOT fallback on schema validation failure" do
    primary = MockProvider.new("gemini")
    fallback = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(primary_provider: primary, fallback_provider: fallback)

    # Require fields that MockProvider does not return
    strict_schema = { required: [:non_existent_field] }

    assert_raises(Ai::ValidationError) do
      router.generate("Test prompt", schema: strict_schema)
    end

    assert_equal 1, primary.calls
    assert_equal 0, fallback.calls
  end

  test "raises AllProvidersFailedError when both primary and fallback fail" do
    gemini_err = Ai::ServerError.new("Gemini 500", provider: "gemini", status_code: 500)
    groq_err = Ai::RateLimitError.new("Groq 429", provider: "groq", status_code: 429)

    primary = FailingProvider.new("gemini", gemini_err)
    fallback = FailingProvider.new("groq", groq_err)

    router = Ai::ProviderRouter.new(primary_provider: primary, fallback_provider: fallback)

    error = assert_raises(Ai::AllProvidersFailedError) do
      router.generate("Test prompt")
    end

    assert_includes error.message, "All AI providers failed"
    assert_equal 3, error.attempts.size # 2 gemini attempts + 1 groq
    assert_equal "gemini", error.attempts[0][:provider]
    assert_equal "gemini", error.attempts[1][:provider]
    assert_equal "groq", error.attempts[2][:provider]
  end
end
