module Ai
  class ProviderRouter
    DEFAULT_MAX_RETRIES = 1
    DEFAULT_RETRY_DELAY = 0.05

    attr_reader :local_provider, :cloud_primary_provider, :cloud_fallback_provider,
                :mode, :cloud_fallback_enabled, :attempts, :max_retries, :retry_delay

    def self.resolve_provider(name)
      case name.to_s.downcase
      when "openai"
        Ai::OpenaiProvider.new
      when "grok", "xai"
        Ai::XaiProvider.new
      when "groq"
        Ai::GroqProvider.new
      when "gemini"
        Ai::GeminiProvider.new
      when "ollama"
        Ai::OllamaProvider.new
      else
        Ai::GeminiProvider.new
      end
    end

    def initialize(
      local_provider: nil,
      cloud_primary_provider: nil,
      cloud_fallback_provider: nil,
      primary_provider: nil,
      fallback_provider: nil,
      mode: nil,
      cloud_fallback_enabled: nil,
      max_retries: DEFAULT_MAX_RETRIES,
      retry_delay: DEFAULT_RETRY_DELAY
    )
      @mode = (mode || Ai::Configuration.mode).to_s.downcase
      @cloud_fallback_enabled = if cloud_fallback_enabled.nil?
        Ai::Configuration.fallback_enabled?
      else
        ActiveModel::Type::Boolean.new.cast(cloud_fallback_enabled)
      end

      if local_provider.nil? && primary_provider.present? && cloud_primary_provider.nil?
        # Backwards-compatibility with 2-tier tests that passed primary_provider and fallback_provider
        @local_provider = primary_provider
        @cloud_primary_provider = fallback_provider
        @cloud_fallback_provider = nil
      else
        @local_provider = local_provider || Ai::OllamaProvider.new
        @cloud_primary_provider = cloud_primary_provider || primary_provider || self.class.resolve_provider(Ai::Configuration.primary_provider)
        # Pass `cloud_fallback_provider: :none` to pin a single cloud provider with no silent fallback.
        @cloud_fallback_provider = if cloud_fallback_provider == :none
          nil
        else
          cloud_fallback_provider || fallback_provider || self.class.resolve_provider(Ai::Configuration.fallback_provider)
        end
      end

      @max_retries = max_retries
      @retry_delay = retry_delay
      @attempts = []
    end

    def primary_provider
      run_local_tier? ? @local_provider : @cloud_primary_provider
    end

    def fallback_provider
      @cloud_fallback_provider || @cloud_primary_provider
    end

    def self.generate(prompt, options = {})
      new.generate(prompt, options)
    end

    def generate(prompt, options = {})
      @attempts = []
      last_error = nil

      # Tier 1: Local Inference (Ollama)
      if run_local_tier?
        response, err, _retries = execute_with_retries(
          @local_provider,
          prompt,
          options,
          fallback_used: false,
          fallback_reason: nil
        )
        return response if response.present?

        last_error = err
        Rails.logger.warn("[AI ProviderRouter] Local provider #{@local_provider.provider_name} failed: #{err.message}.")

        # If cloud fallback is disabled or mode is strictly local, do not contact cloud
        unless cloud_fallback_permitted?
          raise Ai::CloudFallbackDisabledError.new(
            "Local inference (#{@local_provider.provider_name}) failed and cloud fallback is disabled: #{err.message}",
            provider: @local_provider.provider_name,
            raw_response: err.raw_response
          )
        end
      end

      # Tier 2: Cloud Primary (Gemini)
      if @cloud_primary_provider.present?
        fallback_reason = if run_local_tier?
          "Local provider (#{@local_provider.provider_name}) failed: #{last_error&.message}"
        end

        response, err, _retries = execute_with_retries(
          @cloud_primary_provider,
          prompt,
          options,
          fallback_used: run_local_tier?,
          fallback_reason: fallback_reason
        )
        return response if response.present?

        last_error = err
        Rails.logger.warn("[AI ProviderRouter] Cloud primary provider #{@cloud_primary_provider.provider_name} failed: #{err.message}.")
      end

      # Tier 3: Cloud Fallback (Groq / secondary)
      if @cloud_fallback_provider.present? && @cloud_fallback_enabled
        fallback_reason = "Prior providers failed. Last: #{last_error&.message}"
        response, err, _retries = execute_with_retries(
          @cloud_fallback_provider,
          prompt,
          options,
          fallback_used: true,
          fallback_reason: fallback_reason
        )
        return response if response.present?

        last_error = err
        Rails.logger.error("[AI ProviderRouter] Cloud fallback provider #{@cloud_fallback_provider.provider_name} failed: #{err.message}.")
      end

      # Exhausted all available providers
      raise Ai::AllProvidersFailedError.new(
        "All AI providers failed. Last error: #{last_error&.message}",
        attempts: @attempts
      )
    end

    private

    def run_local_tier?
      @mode != "cloud" && @local_provider.present?
    end

    def cloud_fallback_permitted?
      @mode != "local" && @cloud_fallback_enabled
    end

    def execute_with_retries(provider, prompt, options, fallback_used:, fallback_reason: nil)
      retries = 0
      loop do
        begin
          res = execute_provider(
            provider,
            prompt,
            options,
            fallback_used: fallback_used,
            fallback_reason: fallback_reason,
            retry_count: retries
          )
          validated = validate_and_return!(res, options[:schema])
          return [validated, nil, retries]
        rescue Ai::TransientError => e
          record_failure(provider, e)
          if retries < @max_retries
            retries += 1
            Rails.logger.warn("[AI ProviderRouter] #{provider.provider_name} transient error: #{e.message}. Retrying (#{retries}/#{@max_retries})...")
            sleep(@retry_delay) if @retry_delay.positive?
          else
            Rails.logger.warn("[AI ProviderRouter] #{provider.provider_name} failed after #{retries} retries: #{e.message}.")
            return [nil, e, retries]
          end
        end
      end
    end

    def execute_provider(provider, prompt, options, fallback_used:, fallback_reason: nil, retry_count: 0)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = provider.generate(prompt, options)
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0

      record_success(provider, duration_ms: duration_ms, fallback_used: fallback_used)

      metadata = response.metadata.merge(
        router_attempts: @attempts,
        fallback_reason: fallback_reason,
        retry_count: retry_count
      )

      Ai::Response.new(
        raw_content: response.raw_content,
        data: response.data,
        provider: response.provider,
        model: response.model,
        duration_ms: duration_ms,
        fallback_used: fallback_used,
        metadata: metadata
      )
    end

    def validate_and_return!(response, expected_schema)
      Ai::ResponseValidator.validate!(response, expected_schema)
      response
    end

    def record_success(provider, duration_ms:, fallback_used:)
      @attempts << {
        provider: provider.provider_name,
        model: provider.model,
        duration_ms: duration_ms.round(2),
        fallback: fallback_used,
        status: :success,
        timestamp: Time.current
      }
    end

    def record_failure(provider, error)
      @attempts << {
        provider: provider.provider_name,
        model: provider.model,
        error_class: error.class.name,
        error_message: error.message,
        status_code: error.status_code,
        status: :failed,
        timestamp: Time.current
      }
    end
  end
end
