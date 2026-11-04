module Governance
  class ProviderAnalytics
    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    def calculate
      executions = scope.executions

      total_requests = executions.count
      provider_usage = executions.where.not(provider: nil).group(:provider).count
      model_usage = executions.where.not(ai_model: nil).group(:ai_model).count

      successful_requests = executions.where(status: "completed").count
      failed_requests = executions.where(status: "failed").count

      # Fallback count: count only where fallback_used is true
      fallback_count = executions.where(fallback_used: true).count
      fallback_rate = total_requests > 0 ? (fallback_count.to_f / total_requests * 100).round(1) : nil

      # Provider latency in milliseconds from inference_duration
      latencies = executions.where.not(inference_duration: nil)
                            .pluck(:inference_duration)
                            .map { |d| d.to_f * 1000 } # to ms
                            .select { |d| d > 0 }

      avg_latency_ms = latencies.any? ? (latencies.sum / latencies.size).round(1) : nil

      # Latency breakdown per provider
      latency_by_provider = {}
      executions.where.not(inference_duration: nil).group(:provider).average(:inference_duration).each do |prov, dur|
        latency_by_provider[prov] = (dur.to_f * 1000).round(1)
      end

      # Error categories
      error_categories = Hash.new(0)
      executions.where(status: "failed").find_each do |exec|
        cat = exec.error_category || "UNKNOWN_ERROR"
        error_categories[cat] += 1
      end

      # Provider health status summary (zero secret leak)
      provider_statuses = build_provider_statuses(provider_usage, executions)

      {
        total_requests: total_requests,
        successful_requests: successful_requests,
        failed_requests: failed_requests,
        provider_usage: provider_usage,
        model_usage: model_usage,
        fallback_count: fallback_count,
        fallback_rate: fallback_rate,
        avg_latency_ms: avg_latency_ms,
        formatted_avg_latency: format_latency(avg_latency_ms),
        latency_by_provider: latency_by_provider,
        error_categories: error_categories.sort_by { |_, v| -v }.to_h,
        provider_statuses: provider_statuses
      }
    end

    private

    def format_latency(latency_ms)
      return "Unavailable" if latency_ms.nil? || latency_ms <= 0
      if latency_ms < 1000
        "#{latency_ms.round(0)}ms"
      else
        "#{(latency_ms / 1000.0).round(2)}s"
      end
    end

    def build_provider_statuses(provider_usage, executions)
      statuses = {}
      all_providers = (provider_usage.keys + %w[ollama gemini groq]).uniq

      all_providers.each do |p|
        prov_execs = executions.where(provider: p)
        total = prov_execs.count
        failed = prov_execs.where(status: "failed").count
        fallbacks = prov_execs.where(fallback_used: true).count

        health = if total == 0
          "Idle"
        elsif failed == 0
          "Healthy"
        elsif failed.to_f / total > 0.5
          "Degraded"
        else
          "Operational"
        end

        statuses[p] = {
          total: total,
          failed: failed,
          fallbacks: fallbacks,
          health: health
        }
      end

      statuses
    end
  end
end
