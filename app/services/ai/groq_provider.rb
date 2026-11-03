module Ai
  class GroqProvider < BaseProvider
    DEFAULT_MODEL = "llama-3.3-70b-versatile".freeze
    BASE_API_URL = "https://api.groq.com/openai/v1/chat/completions".freeze

    def provider_name
      "groq"
    end

    protected

    def default_api_key
      ENV["GROQ_API_KEY"] || Rails.application.credentials.dig(:groq, :api_key)
    end

    def default_model
      ENV.fetch("GROQ_MODEL", DEFAULT_MODEL)
    end

    def endpoint_uri
      URI.parse(BASE_API_URL)
    end

    def build_http_request(uri, prompt, options)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"

      messages = []
      if options[:system_instruction].present?
        messages << { role: "system", content: options[:system_instruction].to_s }
      end
      messages << { role: "user", content: prompt.to_s }

      payload = {
        model: @model,
        messages: messages,
        temperature: options[:temperature] || 0.2,
        response_format: { type: "json_object" }
      }

      if options[:max_tokens].present?
        payload[:max_tokens] = options[:max_tokens].to_i
      end

      request.body = payload.to_json
      request
    end

    def parse_provider_response(response, duration_ms:)
      parsed = JSON.parse(response.body)
      choice = parsed.dig("choices", 0)

      if choice.nil?
        raise Ai::ValidationError.new("Groq returned an empty choice list", provider: provider_name, raw_response: response.body)
      end

      raw_text = choice.dig("message", "content").to_s.strip
      if raw_text.blank?
        raise Ai::ValidationError.new("Groq returned an empty message content", provider: provider_name, raw_response: response.body)
      end

      # Strip Markdown fences if present (e.g. ```json ... ```)
      cleaned_text = extract_raw_json(raw_text)

      begin
        data = JSON.parse(cleaned_text)
      rescue JSON::ParserError => e
        raise Ai::ValidationError.new("Groq response is not valid JSON: #{e.message.truncate(80)}", provider: provider_name, raw_response: raw_text)
      end

      unless data.is_a?(Hash)
        raise Ai::ValidationError.new("Groq response must be a JSON object, got #{data.class.name}", provider: provider_name, raw_response: raw_text)
      end

      metadata = {
        finish_reason: choice["finish_reason"],
        usage: parsed["usage"]
      }

      Ai::ResponseNormalizer.normalize(
        raw_content: raw_text,
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
