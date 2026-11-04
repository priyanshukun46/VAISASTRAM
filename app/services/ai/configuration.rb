module Ai
  class Configuration
    VALID_MODES = %w[hybrid local cloud].freeze
    VALID_PROVIDERS = %w[openai gemini groq grok xai ollama].freeze

    # Production defaults to cloud (Gemini or OpenAI primary) because a hosted server cannot reach a local Ollama.
    # Development/test default to hybrid. AI_PROVIDER_MODE always wins when set.
    def self.mode
      ENV.fetch("AI_PROVIDER_MODE") { Rails.env.production? ? "cloud" : "hybrid" }.to_s.downcase
    end

    def self.primary_provider
      ENV["AI_PRIMARY_PROVIDER"].presence&.downcase || (mode == "cloud" ? "gemini" : "ollama")
    end

    def self.fallback_provider
      ENV["AI_FALLBACK_PROVIDER"].presence&.downcase || "groq"
    end

    def self.fallback_enabled?
      val = ENV["AI_FALLBACK_ENABLED"].presence || ENV["AI_CLOUD_FALLBACK_ENABLED"].presence || "true"
      val.to_s.downcase == "true"
    end

    def self.cloud_fallback_enabled?
      fallback_enabled?
    end

    def self.openai_enabled?
      ENV.fetch("OPENAI_ENABLED") { ENV["OPENAI_API_KEY"].present? }.to_s.downcase == "true"
    end

    def self.xai_enabled?
      ENV.fetch("XAI_ENABLED") { ENV["XAI_API_KEY"].present? || ENV["GROK_API_KEY"].present? }.to_s.downcase == "true"
    end

    def self.grok_enabled?
      xai_enabled?
    end

    def self.openai_model
      ENV.fetch("OPENAI_MODEL", "gpt-4o")
    end

    def self.xai_model
      ENV.fetch("XAI_MODEL") { ENV.fetch("GROK_MODEL", "grok-2-latest") }
    end

    def self.default_model_choice
      "auto"
    end

    def self.ollama_remote?
      host = URI.parse(ollama_base_url).host.to_s
      host.present? && !%w[localhost 127.0.0.1 ::1 0.0.0.0].include?(host)
    rescue URI::InvalidURIError
      false
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

      if mode == "cloud" && !any_cloud_key_configured? && !Rails.env.test?
        raise Ai::ConfigurationError.new("Cloud inference mode is enabled but no cloud API key is configured (OPENAI_API_KEY, GEMINI_API_KEY, XAI_API_KEY, or GROQ_API_KEY).")
      end
      true
    end

    def self.any_cloud_key_configured?
      ENV["OPENAI_API_KEY"].present? ||
        ENV["GEMINI_API_KEY"].present? ||
        ENV["XAI_API_KEY"].present? ||
        ENV["GROK_API_KEY"].present? ||
        ENV["GROQ_API_KEY"].present?
    end
  end
end
