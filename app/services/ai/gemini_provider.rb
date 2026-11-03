module Ai
  class GeminiProvider < BaseProvider
    DEFAULT_MODEL = "gemini-2.5-pro".freeze
    BASE_API_URL = "https://generativelanguage.googleapis.com/v1beta/models".freeze

    def provider_name
      "gemini"
    end

    protected

    def default_api_key
      ENV["GEMINI_API_KEY"] || Rails.application.credentials.dig(:gemini, :api_key)
    end

    def default_model
      ENV.fetch("GEMINI_MODEL", DEFAULT_MODEL)
    end

    def endpoint_uri
      URI.parse("#{BASE_API_URL}/#{@model}:generateContent?key=#{@api_key}")
    end

    def build_http_request(uri, prompt, options)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"

      payload = {
        contents: [
          {
            role: "user",
            parts: [{ text: prompt }]
          }
        ],
        generationConfig: {
          temperature: options[:temperature] || 0.2,
          responseMimeType: "application/json"
        }
      }

      if options[:system_instruction].present?
        payload[:systemInstruction] = {
          parts: [{ text: options[:system_instruction] }]
        }
      end

      if options[:max_tokens].present?
        payload[:generationConfig][:maxOutputTokens] = options[:max_tokens].to_i
      end

      request.body = payload.to_json
      request
    end

    def parse_provider_response(response, duration_ms:)
      parsed = JSON.parse(response.body)
      candidate = parsed.dig("candidates", 0)

      if candidate.nil?
        raise Ai::ValidationError.new("Gemini returned an empty candidate list", provider: provider_name, raw_response: response.body)
      end

      raw_text = candidate.dig("content", "parts", 0, "text").to_s.strip
      if raw_text.blank?
        raise Ai::ValidationError.new("Gemini returned an empty content part", provider: provider_name, raw_response: response.body)
      end

      # Strip Markdown fences if present (e.g. ```json ... ```)
      cleaned_text = extract_raw_json(raw_text)

      begin
        data = JSON.parse(cleaned_text)
      rescue JSON::ParserError => e
        raise Ai::ValidationError.new("Gemini response is not valid JSON: #{e.message.truncate(80)}", provider: provider_name, raw_response: raw_text)
      end

      unless data.is_a?(Hash)
        raise Ai::ValidationError.new("Gemini response must be a JSON object, got #{data.class.name}", provider: provider_name, raw_response: raw_text)
      end

      metadata = {
        finish_reason: candidate["finishReason"],
        usage: parsed["usageMetadata"]
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
