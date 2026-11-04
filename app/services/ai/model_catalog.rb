module Ai
  # Server-side allowlist of models a user may pick in the workspace dropdown.
  # The browser only ever sends an id; it never chooses a provider class, URL or model string.
  class ModelCatalog
    AUTO = "auto".freeze

    Choice = Struct.new(:id, :label, :hint, :available, :reason, keyword_init: true) do
      def available? = available
    end

    class << self
      def all
        [
          auto_choice,
          Choice.new(id: "ollama", label: "Local · Ollama (#{Configuration.ollama_model})",
                     hint: "Local only, never leaves your machine",
                     available: ollama_server_usable?, reason: "no reachable Ollama server configured"),
          Choice.new(id: "browser", label: "My laptop · Ollama (via browser)",
                     hint: "Runs on your own computer; needs Ollama installed", available: true),
          Choice.new(id: "openai", label: "Cloud · OpenAI (#{openai_model})",
                     hint: "OpenAI GPT only, no fallback", available: key?(:openai, "OPENAI_API_KEY"), reason: "missing API key"),
          Choice.new(id: "gemini", label: "Cloud · Google Gemini (#{gemini_model})",
                     hint: "Google Gemini only, no fallback", available: key?(:gemini, "GEMINI_API_KEY"), reason: "missing API key"),
          Choice.new(id: "grok", label: "Cloud · xAI Grok (#{xai_model})",
                     hint: "xAI Grok only, no fallback", available: key?(:xai, "XAI_API_KEY") || key?(:grok, "GROK_API_KEY"), reason: "missing API key"),
          Choice.new(id: "groq", label: "Cloud · Groq (#{groq_model})",
                     hint: "Groq only, no fallback", available: key?(:groq, "GROQ_API_KEY"), reason: "missing API key")
        ]
      end

      def find(id)
        all.find { |c| c.id == normalize(id) }
      end

      def valid?(id)
        find(id).present?
      end

      def normalize(id)
        id.to_s.strip.downcase.presence || AUTO
      end

      # Returns nil for "auto" so the planner keeps its default (hybrid) router.
      # A specific choice never silently falls back to a different provider.
      def router_for(id)
        case normalize(id)
        when AUTO then nil
        when "ollama"
          Ai::ProviderRouter.new(mode: "local", cloud_fallback_enabled: false)
        when "browser"
          Ai::ProviderRouter.new(mode: "local", cloud_fallback_enabled: false)
        when "openai"
          Ai::ProviderRouter.new(mode: "cloud", cloud_primary_provider: Ai::OpenaiProvider.new,
                                 cloud_fallback_provider: :none)
        when "gemini"
          Ai::ProviderRouter.new(mode: "cloud", cloud_primary_provider: Ai::GeminiProvider.new,
                                 cloud_fallback_provider: :none)
        when "grok", "xai"
          Ai::ProviderRouter.new(mode: "cloud", cloud_primary_provider: Ai::XaiProvider.new,
                                 cloud_fallback_provider: :none)
        when "groq"
          Ai::ProviderRouter.new(mode: "cloud", cloud_primary_provider: Ai::GroqProvider.new,
                                 cloud_fallback_provider: :none)
        else
          raise ArgumentError, "Unknown AI model '#{id}'"
        end
      end

      def options_for_select
        all.map { |c| [c.available? ? c.label : "#{c.label} (#{c.reason})", c.id] }
      end

      def disabled_ids
        all.reject(&:available?).map(&:id)
      end

      def openai_model = Configuration.openai_model
      def gemini_model = ENV.fetch("GEMINI_MODEL", Ai::GeminiProvider::DEFAULT_MODEL)
      def xai_model = Configuration.xai_model
      alias_method :grok_model_name, :xai_model
      def groq_model = ENV.fetch("GROQ_MODEL", Ai::GroqProvider::DEFAULT_MODEL)

      private

      # "Auto" follows the deployment mode: cloud (configured primary) in production, local-first hybrid in development.
      def auto_choice
        if Configuration.mode == "cloud"
          primary = Configuration.primary_provider
          model_name = case primary
          when "openai" then openai_model
          when "grok", "xai" then xai_model
          when "groq" then groq_model
          else gemini_model
          end
          provider_title = case primary
          when "openai" then "OpenAI"
          when "grok", "xai" then "xAI"
          when "groq" then "Groq"
          else "Cloud"
          end

          Choice.new(id: AUTO, label: "Auto · #{model_name} (#{provider_title})",
                     hint: "#{provider_title} first, #{Configuration.fallback_provider.titleize} fallback if configured",
                     available: Configuration.any_cloud_key_configured?,
                     reason: "no cloud API key configured")
        else
          Choice.new(id: AUTO, label: "Auto · #{Configuration.ollama_model} (Hybrid)",
                     hint: "Local first, cloud fallback", available: true)
        end
      end

      # On a hosted server, "localhost" is the server itself, so local Ollama only counts if pointed elsewhere.
      def ollama_server_usable?
        !Rails.env.production? || Configuration.ollama_remote?
      end

      def key?(cred, env)
        ENV[env].present? || Rails.application.credentials.dig(cred, :api_key).present?
      end
    end
  end
end
