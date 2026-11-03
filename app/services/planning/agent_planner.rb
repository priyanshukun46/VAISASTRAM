module Planning
  class UnauthorizedError < StandardError; end

  class AgentPlanner
    class << self
      attr_accessor :default_router_override
    end

    attr_reader :task, :user, :agent, :provider_router

    def initialize(task:, user:, provider_router: nil)
      @task = task
      @user = user
      @agent = task.agent
      @provider_router = provider_router || self.class.default_router_override || Ai::ProviderRouter.new
    end

    def self.plan(task:, user:, provider_router: nil)
      new(task: task, user: user, provider_router: provider_router).plan
    end

    def plan
      # 1. Authorization & Ownership Guard
      verify_task_ownership!

      execution = nil
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        # 2. State Transition: Planning
        @task.update!(status: "planning")

        execution = @task.executions.create!(
          agent: @agent,
          status: "planning",
          provider: "gemini",
          ai_model: "gemini-2.5-pro",
          started_at: Time.current
        )

        # 3. Tool Allowlist Resolution
        tools = resolve_allowed_tools
        allowed_keys = tools.map(&:key)

        # 4. Construct Structured Planning Prompts
        system_prompt = PlanningPrompt.build_system_prompt(agent: @agent, tools: tools)
        user_prompt = PlanningPrompt.build_user_prompt(task: @task)
        schema = PlanSchema.json_schema(available_tools: allowed_keys)

        # 5. Invoke Multi-Provider AI Routing (Gemini -> Groq fallback)
        ai_response = @provider_router.generate(
          user_prompt,
          system_instruction: system_prompt,
          schema: schema
        )

        # 6. Strict Validation (Untrusted AI Output)
        PlanValidator.validate!(ai_response.data, allowed_tools: allowed_keys)

        # 7. Normalization
        normalized_plan = PlanNormalizer.normalize(ai_response.data)

        # 8. Atomic Persistence
        steps = []
        ActiveRecord::Base.transaction do
          execution.update!(
            status: "planned",
            plan: normalized_plan,
            provider: ai_response.provider,
            ai_model: ai_response.model,
            completed_at: Time.current
          )

          @task.update!(status: "planned")

          if normalized_plan["requires_action"]
            normalized_plan["steps"].each do |step_hash|
              steps << execution.agent_steps.create!(
                position: step_hash["step_number"],
                action_key: step_hash["action"],
                arguments: step_hash["arguments"],
                status: "pending", # Initial pending state; strictly no tool execution during planning
                risk_level: "unknown" # AI risk estimation is never trusted; Ruby policy engine decides
              )
            end
          end

          # Immutable Audit Log
          AuditEvent.create!(
            user: @user,
            execution: execution,
            event_type: "plan_generated",
            actor_type: "agent",
            actor_id: @agent.name,
            metadata: {
              goal: normalized_plan["goal"],
              requires_action: normalized_plan["requires_action"],
              steps_count: steps.size,
              clarification_needed: normalized_plan["clarification_needed"],
              explanation: normalized_plan["explanation"],
              provider: ai_response.provider,
              model: ai_response.model,
              duration_ms: ai_response.duration_ms,
              fallback_used: ai_response.fallback?
            }
          )
        end

        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0

        PlanningResult.success(
          plan: normalized_plan,
          task: @task,
          execution: execution,
          steps: steps,
          provider: ai_response.provider,
          model: ai_response.model,
          duration_ms: duration_ms
        )

      rescue StandardError => e
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0
        handle_planning_failure!(execution, e, duration_ms: duration_ms)
      end
    end

    private

    def verify_task_ownership!
      unless @user.can_access?(@task)
        raise UnauthorizedError, "Access Denied: User #{@user.id} is not authorized to plan task #{@task.id}"
      end
    end

    def resolve_allowed_tools
      configured_keys = @agent.configuration["allowed_tools"]
      if configured_keys.present? && configured_keys.is_a?(Array)
        Tool.where(key: configured_keys, enabled: true).order(:key)
      else
        Tool.where(enabled: true).order(:key)
      end
    end

    def handle_planning_failure!(execution, error, duration_ms:)
      @task.update(status: "failed") if @task.persisted?

      if execution&.persisted?
        execution.update(
          status: "failed",
          error_message: error.message,
          completed_at: Time.current
        )

        AuditEvent.create(
          user: @user,
          execution: execution,
          event_type: "planning_failed",
          actor_type: "system",
          actor_id: "agent_planner",
          metadata: {
            error_class: error.class.name,
            error_message: error.message,
            duration_ms: duration_ms
          }
        )
      end

      PlanningResult.failure(
        task: @task,
        execution: execution,
        error: error,
        duration_ms: duration_ms
      )
    end
  end
end
