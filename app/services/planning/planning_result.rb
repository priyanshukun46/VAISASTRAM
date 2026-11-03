module Planning
  class PlanningResult
    attr_reader :plan, :task, :execution, :steps, :error, :provider, :model, :duration_ms

    def initialize(success:, plan: nil, task: nil, execution: nil, steps: [], error: nil, provider: nil, model: nil, duration_ms: 0.0)
      @success = success
      @plan = plan || {}
      @task = task
      @execution = execution
      @steps = steps || []
      @error = error
      @provider = provider
      @model = model
      @duration_ms = duration_ms.to_f.round(2)
    end

    def self.success(plan:, task:, execution:, steps:, provider:, model:, duration_ms:)
      new(
        success: true,
        plan: plan,
        task: task,
        execution: execution,
        steps: steps,
        provider: provider,
        model: model,
        duration_ms: duration_ms
      )
    end

    def self.failure(task:, execution: nil, error:, provider: nil, model: nil, duration_ms: 0.0)
      new(
        success: false,
        task: task,
        execution: execution,
        error: error,
        provider: provider,
        model: model,
        duration_ms: duration_ms
      )
    end

    def success?
      @success
    end

    def failure?
      !@success
    end

    def error_message
      @error.is_a?(Exception) ? @error.message : @error.to_s
    end

    def response_text
      @plan["response"].presence || @plan["summary"].presence || "Plan prepared."
    end

    def requires_action?
      @plan["requires_action"] == true
    end

    def clarification_needed?
      @plan["clarification_needed"].present?
    end

    def clarification_needed
      @plan["clarification_needed"]
    end

    def explanation
      @plan["explanation"]
    end
  end
end
