module Policies
  class Engine
    class << self
      attr_accessor :custom_evaluator
    end

    def self.evaluate(context_or_options)
      context = if context_or_options.is_a?(Policies::Context)
        context_or_options
      else
        Policies::Context.new(**context_or_options)
      end

      new(context: context).evaluate
    end

    attr_reader :context, :evaluator

    def initialize(context:, evaluator: nil)
      @context = context
      @evaluator = evaluator || self.class.custom_evaluator || Policies::Evaluator.new
    end

    def evaluate
      decision = @evaluator.evaluate(@context)

      # Record immutable audit event for every decision (Test 17)
      record_audit_event!(decision)

      # Synchronize decision with AgentStep if step was provided in context
      synchronize_agent_step!(decision) if @context.agent_step.present?

      decision
    end

    private

    def record_audit_event!(decision)
      AuditEvent.create!(
        user: @context.user,
        execution: @context.execution,
        agent_step: @context.agent_step,
        event_type: "policy_evaluated",
        actor_type: "policy_engine",
        actor_id: decision.policy_id,
        occurred_at: decision.evaluation_timestamp,
        metadata: {
          action_key: @context.action_key,
          tool_name: @context.tool&.name,
          decision: decision.decision,
          reason: decision.reason,
          policy_id: decision.policy_id,
          action_fingerprint: decision.action_fingerprint,
          matched_conditions: decision.matched_conditions,
          sanitized_arguments: @context.sanitized_arguments,
          evaluation_timestamp: decision.evaluation_timestamp.iso8601
        }
      )
    rescue StandardError => e
      # Audit failure is logged; audit events are critical
      Rails.logger.error("[VAISASTRAM Policy Engine Audit Failure] #{e.message}")
    end

    def synchronize_agent_step!(decision)
      step = @context.agent_step
      return unless step.persisted?

      updates = { policy_decision: decision.decision }

      case decision.decision
      when Decision::REQUIRE_APPROVAL
        updates[:status] = "waiting_approval"
      when Decision::DENY
        updates[:status] = "blocked"
      end

      step.update_columns(updates)
    rescue StandardError => e
      Rails.logger.error("[VAISASTRAM AgentStep Sync Error] #{e.message}")
    end
  end
end
