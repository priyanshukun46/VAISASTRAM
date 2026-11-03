require "test_helper"

class AiOllamaProviderTest < ActiveSupport::TestCase
  class TestableOllamaProvider < Ai::OllamaProvider
    attr_accessor :mock_response, :mock_exception

    def execute_http_request(prompt, options)
      raise @mock_exception if @mock_exception
      @mock_response
    end
  end

  setup do
    @provider = TestableOllamaProvider.new(
      base_url: "http://localhost:11434",
      model: "gemma3:4b",
      timeout: 5
    )
  end

  test "provider identification" do
    assert_equal "ollama", @provider.provider_name
    assert_equal "gemma3:4b", @provider.model
    assert_equal "http://localhost:11434", @provider.base_url
  end

  test "validates configuration rejects invalid URL" do
    invalid_provider = Ai::OllamaProvider.new(base_url: "not-a-valid-url")
    assert_raises(Ai::ConfigurationError) do
      invalid_provider.generate("Test prompt")
    end
  end

  # Test 1: Ollama successful response
  test "1. successfully parses valid Ollama JSON response" do
    plan_body = {
      goal: "Prepare payment for vendor invoice.",
      response: "I will verify the invoice and prepare a payment request for approval.",
      steps: [
        {
          step_number: 1,
          action: "retrieve_invoice",
          arguments: { invoice_id: "INV-100" },
          description: "Retrieve invoice details."
        }
      ]
    }

    ollama_envelope = {
      model: "gemma3:4b",
      message: {
        role: "assistant",
        content: plan_body.to_json
      },
      done: true,
      total_duration: 150_000_000,
      prompt_eval_count: 24,
      eval_count: 120
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", ollama_envelope)

    res = @provider.generate("Verify invoice INV-100")
    assert_instance_of Ai::Response, res
    assert_equal "ollama", res.provider
    assert_equal "gemma3:4b", res.model
    assert_equal "Prepare payment for vendor invoice.", res["goal"]
    assert_equal "I will verify the invoice and prepare a payment request for approval.", res["response"]
    assert_equal 1, res["steps"].size
    assert_equal "retrieve_invoice", res["steps"][0]["action"]
    assert_equal 24, res.metadata[:prompt_eval_count]
  end

  # Test 2: Ollama connection refused
  test "2. maps Errno::ECONNREFUSED to ConnectionRefusedError" do
    @provider.mock_exception = Errno::ECONNREFUSED.new("Connection refused - connect(2) for 127.0.0.1:11434")
    err = assert_raises(Ai::ConnectionRefusedError) do
      @provider.generate("Test prompt")
    end
    assert_includes err.message, "Connection refused"
    assert_kind_of Ai::TransientError, err
  end

  # Test 3: Ollama read timeout
  test "3. maps Net::ReadTimeout to TimeoutError" do
    @provider.mock_exception = Net::ReadTimeout.new("Net::ReadTimeout with #<TCPSocket:(closed)>")
    err = assert_raises(Ai::TimeoutError) do
      @provider.generate("Test prompt")
    end
    assert_includes err.message, "timed out"
    assert_kind_of Ai::TransientError, err
  end

  # Test 4: Ollama invalid JSON
  test "4. raises ValidationError on malformed JSON content from Ollama" do
    ollama_envelope = {
      model: "gemma3:4b",
      message: {
        role: "assistant",
        content: "This is completely invalid JSON {{{ missing bracket"
      },
      done: true
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", ollama_envelope)

    err = assert_raises(Ai::ValidationError) do
      @provider.generate("Test prompt")
    end
    assert_includes err.message, "Ollama generated content is not valid JSON"
  end

  # Test 5: Ollama model unavailable (HTTP 404)
  test "5. maps HTTP 404 model not found to ModelNotFoundError" do
    error_body = {
      error: "model 'gemma3:4b' not found, try pulling it first"
    }.to_json

    resp_404 = Struct.new(:code, :body).new("404", error_body)
    @provider.mock_response = resp_404
    @provider.define_singleton_method(:execute_http_request) do |_prompt, _options|
      handle_http_errors!(resp_404)
    end

    err = assert_raises(Ai::ModelNotFoundError) do
      @provider.generate("Test prompt")
    end
    assert_includes err.message, "model 'gemma3:4b' not found"
  end

  test "parses JSON wrapped in markdown code fences from Ollama" do
    plan_body = {
      goal: "Process invoice",
      response: "Plan ready",
      steps: []
    }
    fenced_content = "```json\n#{plan_body.to_json}\n```"

    ollama_envelope = {
      model: "gemma3:4b",
      message: {
        role: "assistant",
        content: fenced_content
      },
      done: true
    }.to_json

    @provider.mock_response = Struct.new(:code, :body).new("200", ollama_envelope)

    res = @provider.generate("Test prompt")
    assert_equal "Process invoice", res["goal"]
    assert_equal "Plan ready", res["response"]
  end
end
