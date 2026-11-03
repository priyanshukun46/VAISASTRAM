require "test_helper"
require "net/http"

class OllamaLiveIntegrationTest < ActiveSupport::TestCase
  def setup
    @base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    @model = ENV.fetch("OLLAMA_MODEL", "gemma3:4b")
    @daemon_running = check_ollama_reachable?
  end

  test "live local Ollama daemon integration" do
    unless @daemon_running
      skip "Local Ollama daemon not reachable at #{@base_url}. Skipping live integration test."
    end

    provider = Ai::OllamaProvider.new(base_url: @base_url, model: @model, timeout: 60)

    # Check installed models on the local daemon
    uri = URI.parse("#{@base_url}/api/tags")
    res = Net::HTTP.get_response(uri)
    assert_equal "200", res.code
    models_data = JSON.parse(res.body)["models"] || []
    has_gemma = models_data.any? { |m| m["name"].to_s.start_with?(@model) }

    if has_gemma
      # Model is pulled and available locally: execute live plan generation
      prompt = "Verify invoice INV-100 and prepare payment"
      response = provider.generate(
        prompt,
        system_instruction: "You are an autonomous AI planner. AI proposes. Ruby decides. Output JSON with mode ('action_plan' or 'conversation'), response, steps.",
        schema: Planning::PlanSchema.json_schema(available_tools: ["lookup_invoice", "verify_invoice", "prepare_payment"])
      )

      assert_equal "ollama", response.provider
      assert_equal @model, response.model
      assert_includes Planning::PlanSchema::MODES, response["mode"]
      assert response["response"].present?
      assert response["steps"].is_a?(Array)
    else
      # Model is not pulled yet: verify provider handles 404 model not found gracefully
      err = assert_raises(Ai::ModelNotFoundError) do
        provider.generate("Test prompt")
      end
      assert_includes err.message, "not found"
    end
  end

  private

  def check_ollama_reachable?
    uri = URI.parse("#{@base_url}/api/tags")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 1
    http.read_timeout = 1
    response = http.get(uri.request_uri)
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end
end
