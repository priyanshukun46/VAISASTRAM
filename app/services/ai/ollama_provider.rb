require "net/http"
require "json"
require "uri"

module Ai
  class OllamaProvider < BaseProvider
    DEFAULT_BASE_URL = "http://localhost:11434".freeze
    DEFAULT_MODEL = "gemma3:4b".freeze
    DEFAULT_TIMEOUT = 90
    DEFAULT_KEEP_ALIVE = "5m".freeze

    attr_reader :base_url, :keep_alive

    def initialize(base_url: nil, model: nil, timeout: nil, keep_alive: nil, api_key: nil)
      @base_url = (base_url || default_base_url).to_s.sub(%r{/\z}, "")
      @keep_alive = keep_alive || default_keep_alive
      # Ollama does not use API keys; pass dummy to BaseProvider to bypass generic key check
      super(api_key: api_key || "none", model: model, timeout: timeout)
    end

    def provider_name
      "ollama"
    end

    protected

    def default_base_url
      ENV.fetch("OLLAMA_BASE_URL", DEFAULT_BASE_URL)
    end

    def default_model
      ENV.fetch("OLLAMA_MODEL", DEFAULT_MODEL)
    end

    def default_timeout
      ENV.fetch("OLLAMA_TIMEOUT", ENV.fetch("AI_REQUEST_TIMEOUT", DEFAULT_TIMEOUT)).to_i
    end

    def default_keep_alive
      ENV.fetch("OLLAMA_KEEP_ALIVE", DEFAULT_KEEP_ALIVE)
    end

    def validate_configuration!
      if @base_url.blank?
        raise Ai::ConfigurationError.new("Missing base URL for #{provider_name}. Please set OLLAMA_BASE_URL.", provider: provider_name)
      end

      uri = URI.parse(@base_url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        raise Ai::ConfigurationError.new("Invalid base URL for #{provider_name}: '#{@base_url}'", provider: provider_name)
      end
    rescue URI::InvalidURIError => e
      raise Ai::ConfigurationError.new("Malformed base URL for #{provider_name}: #{e.message}", provider: provider_name)
    end

    def endpoint_uri
      URI.parse("#{@base_url}/api/chat")
    end

    def build_http_request(uri, prompt, options)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"

      messages = []
      if options[:system_instruction].present?
        messages << { role: "system", content: options[:system_instruction] }
      end
      messages << { role: "user", content: prompt }

      payload = {
        model: @model,
        messages: messages,
        stream: false,
        keep_alive: @keep_alive,
        options: {
          temperature: options[:temperature] || 0.2
        }
      }

      # Structured output: pass json schema if provided, else "json"
      if options[:schema].present?
        payload[:format] = options[:schema]
      else
        payload[:format] = "json"
      end

      request.body = payload.to_json
      request
    end

    def parse_provider_response(response, duration_ms:)
      begin
        parsed = JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Ai::ValidationError.new("Ollama returned malformed JSON envelope: #{e.message.truncate(80)}", provider: provider_name, raw_response: response.body)
      end

      unless parsed.is_a?(Hash)
        raise Ai::ValidationError.new("Ollama response root must be a JSON object, got #{parsed.class.name}", provider: provider_name, raw_response: response.body)
      end

      raw_content = parsed.dig("message", "content").to_s.strip
      if raw_content.blank?
        raise Ai::ValidationError.new("Ollama returned an empty message content", provider: provider_name, raw_response: response.body)
      end

      cleaned_text = extract_raw_json(raw_content)

      begin
        data = JSON.parse(cleaned_text)
      rescue JSON::ParserError => e
        raise Ai::ValidationError.new("Ollama generated content is not valid JSON: #{e.message.truncate(80)}", provider: provider_name, raw_response: raw_content)
      end

      unless data.is_a?(Hash)
        raise Ai::ValidationError.new("Ollama response must be a JSON object, got #{data.class.name}", provider: provider_name, raw_response: raw_content)
      end

      metadata = {
        total_duration_ns: parsed["total_duration"],
        load_duration_ns: parsed["load_duration"],
        prompt_eval_count: parsed["prompt_eval_count"],
        eval_count: parsed["eval_count"],
        done: parsed["done"]
      }

      Ai::ResponseNormalizer.normalize(
        raw_content: raw_content,
        data: data,
        provider: provider_name,
        model: @model,
        duration_ms: duration_ms,
        metadata: metadata
      )
    end

    private

    def extract_raw_json(text)
      trimmed = text.to_s.strip
      if trimmed.start_with?("```")
        trimmed = trimmed.sub(/\A```(?:json)?\s*\n?/i, "")
        trimmed = trimmed.sub(/\n?```\s*\z/, "")
      end
      trimmed.strip
    end
  end
end
