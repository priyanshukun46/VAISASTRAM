require "test_helper"

class Ai::ProductionDefaultsTest < ActiveSupport::TestCase
  PROD = ActiveSupport::EnvironmentInquirer.new("production")

  class << self
    # Support stubbing on Object if minitest/mock is not loaded
    unless Object.method_defined?(:stub)
      def define_stub_helper
        Object.class_eval do
          def stub(name, val_or_callable, *args)
            new_name = "__minitest_stub__#{name}__#{rand(1_000_000)}"
            metaclass = class << self; self; end
            if respond_to?(name, true)
              metaclass.send :alias_method, new_name, name
            end
            metaclass.send :define_method, name do |*a, **kw, &b|
              val_or_callable.respond_to?(:call) ? val_or_callable.call(*a, **kw, &b) : val_or_callable
            end
            yield self
          ensure
            metaclass.send :undef_method, name
            if metaclass.method_defined?(new_name) || metaclass.private_method_defined?(new_name)
              metaclass.send :alias_method, name, new_name
              metaclass.send :undef_method, new_name
            end
          end
        end
      end
    end
  end
  define_stub_helper if respond_to?(:define_stub_helper)

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "mode defaults to hybrid outside production" do
    with_env("AI_PROVIDER_MODE" => nil) { assert_equal "hybrid", Ai::Configuration.mode }
  end

  test "mode defaults to cloud in production" do
    with_env("AI_PROVIDER_MODE" => nil) do
      Rails.stub(:env, PROD) { assert_equal "cloud", Ai::Configuration.mode }
    end
  end

  test "AI_PROVIDER_MODE overrides the production default" do
    with_env("AI_PROVIDER_MODE" => "hybrid") do
      Rails.stub(:env, PROD) { assert_equal "hybrid", Ai::Configuration.mode }
    end
  end

  test "default router in production is cloud with Gemini as primary" do
    with_env("AI_PROVIDER_MODE" => nil, "GEMINI_API_KEY" => "test-key") do
      Rails.stub(:env, PROD) do
        router = Ai::ProviderRouter.new
        assert_equal "cloud", router.mode
        assert_equal "gemini", router.primary_provider.provider_name
      end
    end
  end

  test "Auto means Gemini in production and is available once a key is set" do
    with_env("AI_PROVIDER_MODE" => nil, "GEMINI_API_KEY" => "test-key", "GROQ_API_KEY" => nil) do
      Rails.stub(:env, PROD) do
        auto = Ai::ModelCatalog.find("auto")
        assert_match(/Cloud/, auto.label)
        assert_match(/gemini/i, auto.label)
        assert auto.available?
      end
    end
  end

  test "local Ollama is not offered in production unless pointed at a remote host" do
    Rails.stub(:env, PROD) do
      with_env("OLLAMA_BASE_URL" => "http://localhost:11434") do
        assert_not Ai::ModelCatalog.find("ollama").available?
      end
      with_env("OLLAMA_BASE_URL" => "http://ollama.internal:11434") do
        assert Ai::ModelCatalog.find("ollama").available?
      end
    end
  end

  test "AI_PRIMARY_PROVIDER=openai and AI_FALLBACK_PROVIDER=grok router configuration" do
    with_env(
      "AI_PROVIDER_MODE" => "cloud",
      "AI_PRIMARY_PROVIDER" => "openai",
      "AI_FALLBACK_PROVIDER" => "grok",
      "AI_FALLBACK_ENABLED" => "true",
      "OPENAI_API_KEY" => "test-openai-key",
      "XAI_API_KEY" => "test-xai-key"
    ) do
      assert_equal "openai", Ai::Configuration.primary_provider
      assert_equal "grok", Ai::Configuration.fallback_provider
      assert Ai::Configuration.fallback_enabled?
      assert Ai::Configuration.openai_enabled?
      assert Ai::Configuration.xai_enabled?

      router = Ai::ProviderRouter.new
      assert_equal "cloud", router.mode
      assert_equal "openai", router.primary_provider.provider_name
      assert_equal "grok", router.fallback_provider.provider_name
    end
  end

  test "ModelCatalog includes OpenAI and Grok" do
    with_env("OPENAI_API_KEY" => "key", "XAI_API_KEY" => "key") do
      openai_choice = Ai::ModelCatalog.find("openai")
      assert openai_choice.present?
      assert openai_choice.available?
      assert_match(/gpt/i, openai_choice.label)

      grok_choice = Ai::ModelCatalog.find("grok")
      assert grok_choice.present?
      assert grok_choice.available?
      assert_match(/grok/i, grok_choice.label)
    end
  end
end
