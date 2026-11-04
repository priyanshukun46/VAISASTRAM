module Planning
  class UnauthorizedError < StandardError; end

  class AgentPlanner
    class << self
      attr_accessor :default_router_override
    end

    attr_reader :task, :user, :agent, :provider_router, :context_task

    def initialize(task:, user:, provider_router: nil, context_task: nil)
      @task = task
      @user = user
      @agent = task.agent
      @provider_router = provider_router || self.class.default_router_override || Ai::ProviderRouter.new
      @context_task = context_task
    end

    def self.plan(task:, user:, provider_router: nil, context_task: nil)
      new(task: task, user: user, provider_router: provider_router, context_task: context_task).plan
    end

    def plan
      # 1. Authorization & Ownership Guard
      verify_task_ownership!

      execution = nil
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        # 2. State Transition: Planning
        @task.update!(status: "planning")

        init_provider = @provider_router.respond_to?(:primary_provider) ? @provider_router.primary_provider.provider_name : "ollama"
        init_model = @provider_router.respond_to?(:primary_provider) ? @provider_router.primary_provider.model : "gemma3:4b"

        execution = @task.executions.create!(
          agent: @agent,
          status: "planning",
          provider: init_provider,
          ai_model: init_model,
          started_at: Time.current
        )

        # 3. Tool Allowlist Resolution
        tools = resolve_allowed_tools
        allowed_keys = tools.map(&:key)

        # 4. Construct Structured Planning Prompts
        system_prompt = PlanningPrompt.build_system_prompt(agent: @agent, tools: tools)
        user_prompt = PlanningPrompt.build_user_prompt(task: @task, context_task: @context_task)
        schema = PlanSchema.json_schema(available_tools: allowed_keys)

        # 5. Invoke Multi-Provider AI Routing (Gemini -> Groq fallback)
        ai_response = @provider_router.generate(
          user_prompt,
          system_instruction: system_prompt,
          schema: schema
        )

        # 6. Normalize valid model responses (aliases, casing, arguments)
        normalized_plan = PlanNormalizer.normalize(ai_response.data)

        # 7. Strict Validation (Untrusted AI Output)
        PlanValidator.validate!(normalized_plan, allowed_tools: allowed_keys)

        # 8. Atomic Persistence
        steps = []
        ActiveRecord::Base.transaction do
          execution.update!(
            status: "planned",
            plan: normalized_plan,
            provider: ai_response.provider,
            ai_model: ai_response.model,
            inference_duration: ai_response.duration_ms,
            fallback_used: ai_response.fallback?,
            fallback_reason: ai_response.metadata[:fallback_reason],
            retry_count: ai_response.metadata[:retry_count] || 0,
            completed_at: Time.current
          )

          @task.update!(status: "planned")

          if normalized_plan["mode"] == "action_plan" && normalized_plan["requires_action"]
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

          # Record AI provider selection & fallback in audit trail
          Audit::Recorder.record(
            event_type: "ai_provider_selected",
            actor_type: "system",
            actor_id: "agent_planner",
            user: @user,
            task: @task,
            execution: execution,
            metadata: {
              provider: ai_response.provider,
              model: ai_response.model,
              duration_ms: ai_response.duration_ms
            }
          )

          if ai_response.fallback?
            Audit::Recorder.record(
              event_type: "ai_provider_fallback_used",
              actor_type: "system",
              actor_id: "agent_planner",
              user: @user,
              task: @task,
              execution: execution,
              metadata: {
                primary_failed: true,
                fallback_provider: ai_response.provider,
                fallback_reason: ai_response.metadata[:fallback_reason]
              }
            )
          end

          Audit::Recorder.record!(
            event_type: "plan_validated",
            actor_type: "system",
            actor_id: "plan_validator",
            user: @user,
            task: @task,
            execution: execution,
            metadata: {
              mode: normalized_plan["mode"],
              steps_count: steps.size,
              requires_action: normalized_plan["requires_action"]
            }
          )

          # Immutable Audit Log for plan output
          event_type = normalized_plan["mode"] == "conversation" ? "conversation_replied" : "plan_generated"
          Audit::Recorder.record!(
            user: @user,
            task: @task,
            execution: execution,
            event_type: event_type,
            actor_type: "agent",
            actor_id: @agent.name,
            metadata: {
              mode: normalized_plan["mode"],
              goal: normalized_plan["goal"],
              requires_action: normalized_plan["requires_action"],
              steps_count: steps.size,
              clarification_needed: normalized_plan["clarification_needed"],
              explanation: normalized_plan["explanation"],
              provider: ai_response.provider,
              model: ai_response.model,
              duration_ms: ai_response.duration_ms,
              fallback_used: ai_response.fallback?,
              fallback_reason: ai_response.metadata[:fallback_reason],
              retry_count: ai_response.metadata[:retry_count] || 0
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

        Audit::Recorder.record(
          user: @user,
          task: @task,
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

        Audit::Recorder.record(
          user: @user,
          task: @task,
          execution: execution,
          event_type: "plan_rejected",
          actor_type: "system",
          actor_id: "plan_validator",
          metadata: {
            reason: error.message
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
