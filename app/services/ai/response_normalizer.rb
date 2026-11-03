module Ai
  class ResponseNormalizer
    def self.normalize(raw_content:, data:, provider:, model:, duration_ms:, fallback_used: false, metadata: {})
      new.normalize(
        raw_content: raw_content,
        data: data,
        provider: provider,
        model: model,
        duration_ms: duration_ms,
        fallback_used: fallback_used,
        metadata: metadata
      )
    end

    def normalize(raw_content:, data:, provider:, model:, duration_ms:, fallback_used: false, metadata: {})
      clean_data = clean_data_structure(data, raw_content)

      Ai::Response.new(
        raw_content: raw_content.to_s,
        data: clean_data,
        provider: provider.to_s,
        model: model.to_s,
        duration_ms: duration_ms,
        fallback_used: fallback_used,
        metadata: metadata
      )
    end

    private

    def clean_data_structure(data, raw_content)
      if data.is_a?(Hash)
        # Unwrap nested plan wrapper if provider wrapped top-level object
        if !data.key?("goal") && !data.key?(:goal)
          nested = data["plan"] || data[:plan] || data["execution_plan"] || data[:execution_plan]
          return nested if nested.is_a?(Hash) && (nested.key?("goal") || nested.key?(:goal))
        end
        return data
      end

      if data.is_a?(Array)
        return { "items" => data }
      end

      # Attempt to unwrap string if accidentally double-encoded
      if data.is_a?(String)
        unwrapped = JSON.parse(data) rescue nil
        return unwrapped if unwrapped.is_a?(Hash)
      end

      { "value" => data, "raw" => raw_content }
    end
  end
end
