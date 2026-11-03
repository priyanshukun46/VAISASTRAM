module Ai
  class ResponseValidator
    MAX_RESPONSE_BYTESIZE = 1_048_576 # 1 MB maximum response size to prevent memory exhaustion

    def self.validate!(response_or_data, expected_schema = nil)
      new.validate!(response_or_data, expected_schema)
    end

    def self.parse_json!(raw_text)
      new.parse_json!(raw_text)
    end

    def parse_json!(raw_text)
      if raw_text.nil? || raw_text.to_s.strip.empty?
        raise Ai::ValidationError.new("Empty response received from AI model")
      end

      if raw_text.bytesize > MAX_RESPONSE_BYTESIZE
        raise Ai::ValidationError.new("Response size (#{raw_text.bytesize} bytes) exceeds safety limit of #{MAX_RESPONSE_BYTESIZE} bytes")
      end

      # Strip accidental markdown code blocks
      cleaned = strip_markdown_fences(raw_text)

      begin
        parsed = JSON.parse(cleaned)
      rescue JSON::ParserError => e
        raise Ai::ValidationError.new("Malformed JSON from AI model: #{e.message.truncate(100)}", raw_response: raw_text)
      end

      unless parsed.is_a?(Hash)
        raise Ai::ValidationError.new("Expected root JSON object to be a Hash, received #{parsed.class.name}", raw_response: raw_text)
      end

      parsed
    end

    def validate!(target, expected_schema = nil)
      data = if target.is_a?(Ai::Response)
               target.data
             elsif target.is_a?(String)
               parse_json!(target)
             elsif target.is_a?(Hash)
               target
             else
               raise Ai::ValidationError.new("Invalid target for validation: expected Hash, String, or Ai::Response")
             end

      # If a specific schema is provided, validate against it
      if expected_schema.present?
        validate_against_schema!(data, expected_schema)
      else
        # Validate standard generic structured contract
        validate_generic_contract!(data)
      end

      data
    end

    private

    def strip_markdown_fences(text)
      trimmed = text.strip
      if trimmed.start_with?("```")
        trimmed = trimmed.sub(/\A```(?:json)?\s*\n?/i, "")
        trimmed = trimmed.sub(/\n?```\s*\z/, "")
      end
      trimmed.strip
    end

    def validate_generic_contract!(data)
      # Generic structured response specification:
      # {
      #   "status": "success",
      #   "message": "...",
      #   "data": { ... }
      # }
      unless data.key?("status") || data.key?(:status)
        raise Ai::ValidationError.new("Response missing required 'status' field")
      end

      status_val = data["status"] || data[:status]
      unless status_val.is_a?(String) && %w[success error pending].include?(status_val.to_s.downcase)
        raise Ai::ValidationError.new("Field 'status' must be one of 'success', 'error', 'pending', got #{status_val.inspect}")
      end

      # Validate data payload if present
      payload = data["data"] || data[:data]
      if payload.present? && !payload.is_a?(Hash) && !payload.is_a?(Array)
        raise Ai::ValidationError.new("Field 'data' must be an Object (Hash) or List (Array), got #{payload.class.name}")
      end

      # Disallow dangerous code injection patterns
      detect_suspicious_payloads!(data)
    end

    def validate_against_schema!(data, schema)
      # Check required fields
      if schema[:required].is_a?(Array)
        schema[:required].each do |field|
          field_s = field.to_s
          field_sym = field.to_sym
          unless data.key?(field_s) || data.key?(field_sym)
            raise Ai::ValidationError.new("Missing required field '#{field}' in AI response")
          end
        end
      end

      # Check field types
      if schema[:types].is_a?(Hash)
        schema[:types].each do |field, expected_types|
          val = data[field.to_s] || data[field.to_sym]
          next if val.nil? # Missing check handled by :required

          allowed_classes = Array(expected_types)
          unless allowed_classes.any? { |cls| val.is_a?(cls) }
            expected_names = allowed_classes.map(&:name).join(" or ")
            raise Ai::ValidationError.new("Field '#{field}' has invalid type #{val.class.name} (expected #{expected_names})")
          end
        end
      end

      detect_suspicious_payloads!(data)
    end

    def detect_suspicious_payloads!(data)
      # Recursively inspect keys and string values for dangerous command execution attempts
      deep_inspect(data)
    end

    def deep_inspect(obj, depth = 0)
      return if depth > 10

      if obj.is_a?(Hash)
        obj.each do |k, v|
          if k.to_s =~ /\A(__eval__|__exec__|__rails__|system|exec)\z/i
            raise Ai::ValidationError.new("Potentially malicious key detected in AI response: #{k}")
          end
          deep_inspect(v, depth + 1)
        end
      elsif obj.is_a?(Array)
        obj.each { |item| deep_inspect(item, depth + 1) }
      end
    end
  end
end
