module Ai
  class ProviderRouter
    DEFAULT_MAX_RETRIES = 1
    DEFAULT_RETRY_DELAY = 0.05

    attr_reader :primary_provider, :fallback_provider, :attempts, :max_retries, :retry_delay

    def initialize(primary_provider: nil, fallback_provider: nil, max_retries: DEFAULT_MAX_RETRIES, retry_delay: DEFAULT_RETRY_DELAY)
      @primary_provider = primary_provider || Ai::GeminiProvider.new
      @fallback_provider = fallback_provider || Ai::GroqProvider.new
      @max_retries = max_retries
      @retry_delay = retry_delay
      @attempts = []
    end

    def self.generate(prompt, options = {})
      new.generate(prompt, options)
    end

    def generate(prompt, options = {})
      @attempts = []
      expected_schema = options[:schema]

      # 1. Attempt Primary Provider with Bounded Retries on Transient Errors
      primary_retries = 0
      last_primary_error = nil

      loop do
        begin
          response = execute_provider(@primary_provider, prompt, options, fallback_used: false)
          return validate_and_return!(response, expected_schema)
        rescue Ai::TransientError => e
          last_primary_error = e
          record_failure(@primary_provider, e)

          if primary_retries < @max_retries
            primary_retries += 1
            Rails.logger.warn("[AI ProviderRouter] Primary provider #{@primary_provider.provider_name} transient error: #{e.message}. Retrying (#{primary_retries}/#{@max_retries})...")
            sleep(@retry_delay) if @retry_delay.positive?
          else
            Rails.logger.warn("[AI ProviderRouter] Primary provider #{@primary_provider.provider_name} failed after #{primary_retries} retries: #{e.message}. Initiating fallback to #{@fallback_provider.provider_name}...")
            break
          end
        end
      end

      # 2. Attempt Fallback Provider (Groq) with Identical Logical Request
      begin
        response = execute_provider(@fallback_provider, prompt, options, fallback_used: true)
        validate_and_return!(response, expected_schema)
      rescue Ai::Error => fallback_err
        record_failure(@fallback_provider, fallback_err)
        Rails.logger.error("[AI ProviderRouter] Fallback provider #{@fallback_provider.provider_name} also failed: #{fallback_err.message}")

        raise Ai::AllProvidersFailedError.new(
          "All AI providers failed. Primary (#{@primary_provider.provider_name}): #{last_primary_error&.message}; Fallback (#{@fallback_provider.provider_name}): #{fallback_err.message}",
          attempts: @attempts
        )
      end
    end

    private

    def execute_provider(provider, prompt, options, fallback_used:)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = provider.generate(prompt, options)
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0

      record_success(provider, duration_ms: duration_ms, fallback_used: fallback_used)

      # Mark fallback_used on response if applicable
      if fallback_used
        Ai::Response.new(
          raw_content: response.raw_content,
          data: response.data,
          provider: response.provider,
          model: response.model,
          duration_ms: duration_ms,
          fallback_used: true,
          metadata: response.metadata.merge(router_attempts: @attempts)
        )
      else
        response
      end
    end

    def validate_and_return!(response, expected_schema)
      # Validate structured response
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
