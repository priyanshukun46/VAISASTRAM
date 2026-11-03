module Ai
  class Configuration
    VALID_MODES = %w[hybrid local cloud].freeze

    def self.mode
      ENV.fetch("AI_PROVIDER_MODE", "hybrid").to_s.downcase
    end

    def self.cloud_fallback_enabled?
      ENV.fetch("AI_CLOUD_FALLBACK_ENABLED", "true").to_s.downcase == "true"
    end

    def self.ollama_base_url
      ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    end

    def self.ollama_model
      ENV.fetch("OLLAMA_MODEL", "gemma3:4b")
    end

    def self.ollama_timeout
      ENV.fetch("OLLAMA_TIMEOUT", "90").to_i
    end

    def self.validate!
      unless VALID_MODES.include?(mode)
        raise Ai::ConfigurationError.new("Invalid AI_PROVIDER_MODE '#{mode}'. Allowed modes: #{VALID_MODES.join(', ')}")
      end

      if mode == "cloud" && ENV["GEMINI_API_KEY"].blank? && ENV["GROQ_API_KEY"].blank? && !Rails.env.test?
        raise Ai::ConfigurationError.new("Cloud inference mode is enabled but neither GEMINI_API_KEY nor GROQ_API_KEY is configured.")
      end
      true
    end
  end
end
