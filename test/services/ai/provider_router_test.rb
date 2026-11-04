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
    assert_equal 4, error.attempts.size # 2 gemini attempts + 2 groq attempts
    assert_equal "gemini", error.attempts[0][:provider]
    assert_equal "gemini", error.attempts[1][:provider]
    assert_equal "groq", error.attempts[2][:provider]
    assert_equal "groq", error.attempts[3][:provider]
  end

  # ==========================================
  # Section 10 Hybrid 3-Tier Integration Tests
  # ==========================================

  # Test 13: Local success without any cloud request
  test "13. local Ollama success returns immediately without making any cloud requests" do
    ollama = MockProvider.new("ollama", model: "gemma3:4b")
    gemini = MockProvider.new("gemini", model: "gemini-2.5-pro")
    groq = MockProvider.new("groq", model: "llama-3.3-70b-versatile")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid"
    )

    response = router.generate("Plan payment for INV-100")

    assert_equal "ollama", response.provider
    assert_equal "gemma3:4b", response.model
    assert_not response.fallback?
    assert_equal 1, ollama.calls
    assert_equal 0, gemini.calls, "Gemini cloud provider must NEVER be called when Ollama succeeds"
    assert_equal 0, groq.calls, "Groq cloud provider must NEVER be called when Ollama succeeds"
  end

  # Test 6: Ollama failure followed by Gemini success
  test "6. Ollama transient failure falls back to Gemini successfully" do
    ollama_err = Ai::ConnectionRefusedError.new("Connection refused on 11434", provider: "ollama")
    ollama = FailingProvider.new("ollama", ollama_err)
    gemini = MockProvider.new("gemini", model: "gemini-2.5-pro")
    groq = MockProvider.new("groq", model: "llama-3.3-70b-versatile")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid",
      cloud_fallback_enabled: true
    )

    response = router.generate("Plan payment for INV-100")

    assert_equal "gemini", response.provider
    assert response.fallback?
    assert_includes response.metadata[:fallback_reason], "Local provider (ollama) failed"
    assert_operator ollama.calls, :>=, 1
    assert_equal 1, gemini.calls
    assert_equal 0, groq.calls, "Groq must not be called when Gemini succeeds"
  end

  # Test 7: Ollama and Gemini failure followed by Groq success
  test "7. Ollama and Gemini transient failures fall back to Groq successfully" do
    ollama_err = Ai::TimeoutError.new("Ollama timed out", provider: "ollama")
    gemini_err = Ai::ServerError.new("Gemini 503 unavailable", provider: "gemini", status_code: 503)

    ollama = FailingProvider.new("ollama", ollama_err)
    gemini = FailingProvider.new("gemini", gemini_err)
    groq = MockProvider.new("groq", model: "llama-3.3-70b-versatile")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid",
      cloud_fallback_enabled: true
    )

    response = router.generate("Plan payment for INV-100")

    assert_equal "groq", response.provider
    assert response.fallback?
    assert_operator ollama.calls, :>=, 1
    assert_operator gemini.calls, :>=, 1
    assert_equal 1, groq.calls
  end

  # Test 8: All providers unavailable
  test "8. raises AllProvidersFailedError when local and all cloud providers fail" do
    ollama_err = Ai::ConnectionRefusedError.new("Ollama down", provider: "ollama")
    gemini_err = Ai::TimeoutError.new("Gemini timed out", provider: "gemini")
    groq_err = Ai::ServerError.new("Groq 500 error", provider: "groq", status_code: 500)

    ollama = FailingProvider.new("ollama", ollama_err)
    gemini = FailingProvider.new("gemini", gemini_err)
    groq = FailingProvider.new("groq", groq_err)

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid",
      cloud_fallback_enabled: true
    )

    err = assert_raises(Ai::AllProvidersFailedError) do
      router.generate("Plan payment")
    end
    assert_includes err.message, "All AI providers failed"
  end

  # Test 9: Invalid Gemini API key
  test "9. invalid Gemini API key fails fast and does not fallback to Groq" do
    ollama_err = Ai::ConnectionRefusedError.new("Ollama down", provider: "ollama")
    auth_err = Ai::AuthenticationError.new("Invalid Gemini Key", provider: "gemini", status_code: 401)

    ollama = FailingProvider.new("ollama", ollama_err)
    gemini = FailingProvider.new("gemini", auth_err)
    groq = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid",
      cloud_fallback_enabled: true
    )

    assert_raises(Ai::AuthenticationError) do
      router.generate("Plan payment")
    end
    assert_equal 0, groq.calls, "Must not fallback to Groq when Gemini key is invalid"
  end

  # Test 10: Invalid Groq API key
  test "10. invalid Groq API key fails fast" do
    ollama_err = Ai::ConnectionRefusedError.new("Ollama down", provider: "ollama")
    gemini_err = Ai::TimeoutError.new("Gemini timed out", provider: "gemini")
    auth_err = Ai::AuthenticationError.new("Invalid Groq Key", provider: "groq", status_code: 401)

    ollama = FailingProvider.new("ollama", ollama_err)
    gemini = FailingProvider.new("gemini", gemini_err)
    groq = FailingProvider.new("groq", auth_err)

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid",
      cloud_fallback_enabled: true
    )

    assert_raises(Ai::AuthenticationError) do
      router.generate("Plan payment")
    end
  end

  # Test 11: Schema validation failure
  test "11. schema validation failure does NOT fallback" do
    ollama = MockProvider.new("ollama")
    gemini = MockProvider.new("gemini")
    groq = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid"
    )

    strict_schema = { required: [:mandatory_non_existent_key] }
    assert_raises(Ai::ValidationError) do
      router.generate("Plan payment", schema: strict_schema)
    end
    assert_equal 1, ollama.calls
    assert_equal 0, gemini.calls
    assert_equal 0, groq.calls
  end

  # Test 12: Cloud fallback disabled
  test "12. raises CloudFallbackDisabledError when Ollama fails and cloud fallback is disabled" do
    ollama_err = Ai::ConnectionRefusedError.new("Ollama down", provider: "ollama")
    ollama = FailingProvider.new("ollama", ollama_err)
    gemini = MockProvider.new("gemini")
    groq = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "hybrid",
      cloud_fallback_enabled: false
    )

    err = assert_raises(Ai::CloudFallbackDisabledError) do
      router.generate("Plan payment")
    end
    assert_includes err.message, "cloud fallback is disabled"
    assert_equal 0, gemini.calls, "Cloud provider must not be called when fallback is disabled"
    assert_equal 0, groq.calls, "Cloud provider must not be called when fallback is disabled"
  end

  test "mode local strictly uses Ollama only and never attempts cloud" do
    ollama_err = Ai::TimeoutError.new("Ollama timeout", provider: "ollama")
    ollama = FailingProvider.new("ollama", ollama_err)
    gemini = MockProvider.new("gemini")
    groq = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "local"
    )

    assert_raises(Ai::CloudFallbackDisabledError) do
      router.generate("Plan payment")
    end
    assert_equal 0, gemini.calls
    assert_equal 0, groq.calls
  end

  test "mode cloud skips local Ollama and directly uses Gemini" do
    ollama = MockProvider.new("ollama")
    gemini = MockProvider.new("gemini")
    groq = MockProvider.new("groq")

    router = Ai::ProviderRouter.new(
      local_provider: ollama,
      cloud_primary_provider: gemini,
      cloud_fallback_provider: groq,
      mode: "cloud"
    )

    res = router.generate("Plan payment")
    assert_equal "gemini", res.provider
    assert_equal 0, ollama.calls, "Ollama must be skipped in cloud mode"
    assert_equal 1, gemini.calls
  end

  test "resolve_provider creates appropriate provider instances" do
    assert_instance_of Ai::OpenaiProvider, Ai::ProviderRouter.resolve_provider("openai")
    assert_instance_of Ai::XaiProvider, Ai::ProviderRouter.resolve_provider("grok")
    assert_instance_of Ai::XaiProvider, Ai::ProviderRouter.resolve_provider("xai")
    assert_instance_of Ai::GroqProvider, Ai::ProviderRouter.resolve_provider("groq")
    assert_instance_of Ai::GeminiProvider, Ai::ProviderRouter.resolve_provider("gemini")
    assert_instance_of Ai::OllamaProvider, Ai::ProviderRouter.resolve_provider("ollama")
  end

  test "mode cloud respects AI_PRIMARY_PROVIDER=openai and AI_FALLBACK_PROVIDER=grok" do
    ENV["AI_PRIMARY_PROVIDER"] = "openai"
    ENV["AI_FALLBACK_PROVIDER"] = "grok"
    ENV["AI_PROVIDER_MODE"] = "cloud"

    router = Ai::ProviderRouter.new
    assert_equal "openai", router.primary_provider.provider_name
    assert_equal "grok", router.fallback_provider.provider_name
  ensure
    ENV.delete("AI_PRIMARY_PROVIDER")
    ENV.delete("AI_FALLBACK_PROVIDER")
    ENV.delete("AI_PROVIDER_MODE")
  end

  test "mode cloud does not invoke fallback provider when cloud_fallback_enabled is false" do
    primary_err = Ai::ServerError.new("Primary 500", provider: "primary", status_code: 500)
    primary = FailingProvider.new("primary", primary_err)
    fallback = MockProvider.new("fallback")

    router = Ai::ProviderRouter.new(
      cloud_primary_provider: primary,
      cloud_fallback_provider: fallback,
      mode: "cloud",
      cloud_fallback_enabled: false
    )

    assert_raises(Ai::AllProvidersFailedError) do
      router.generate("Plan payment")
    end

    assert_equal 0, fallback.calls, "Fallback must not be called when cloud_fallback_enabled is false"
  end
end
