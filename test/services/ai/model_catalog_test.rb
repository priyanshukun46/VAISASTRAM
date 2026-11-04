require "test_helper"

class Ai::ModelCatalogTest < ActiveSupport::TestCase
  test "auto and unknown handling" do
    assert Ai::ModelCatalog.valid?(nil)
    assert Ai::ModelCatalog.valid?("auto")
    assert_not Ai::ModelCatalog.valid?("gpt-evil")
    assert_nil Ai::ModelCatalog.router_for("auto")
    assert_raises(ArgumentError) { Ai::ModelCatalog.router_for("gpt-evil") }
  end

  test "ollama choice is local only and never contacts cloud" do
    router = Ai::ModelCatalog.router_for("ollama")
    assert_equal "local", router.mode
    assert_equal false, router.cloud_fallback_enabled
  end

  test "pinned cloud choices have no silent fallback provider" do
    gemini = Ai::ModelCatalog.router_for("gemini")
    assert_equal "cloud", gemini.mode
    assert_equal "gemini", gemini.cloud_primary_provider.provider_name
    assert_nil gemini.cloud_fallback_provider

    groq = Ai::ModelCatalog.router_for("groq")
    assert_equal "groq", groq.cloud_primary_provider.provider_name
    assert_nil groq.cloud_fallback_provider

    openai = Ai::ModelCatalog.router_for("openai")
    assert_equal "cloud", openai.mode
    assert_equal "openai", openai.cloud_primary_provider.provider_name
    assert_nil openai.cloud_fallback_provider

    grok = Ai::ModelCatalog.router_for("grok")
    assert_equal "cloud", grok.mode
    assert_equal "grok", grok.cloud_primary_provider.provider_name
    assert_nil grok.cloud_fallback_provider
  end

  test "auto and ollama are always available" do
    assert Ai::ModelCatalog.find("auto").available?
    assert Ai::ModelCatalog.find("ollama").available?
  end
end
