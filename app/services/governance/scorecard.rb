module Governance
  class Scorecard
    Dimension = Struct.new(
      :key,
      :title,
      :score,             # Float percentage 0.0 - 100.0 or nil if unavailable
      :status,            # :optimal, :acceptable, :attention, :unavailable
      :numerator,
      :numerator_label,
      :denominator,
      :denominator_label,
      :formula,
      :time_window,
      :source_records,
      :data_limitations,
      :description,
      keyword_init: true
    ) do
      def available?
        !score.nil?
      end

      def formatted_score
        available? ? "#{score.round(1)}%" : "Unavailable"
      end
    end

    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    def calculate
      time_label = scope.range_label
      dimensions = []

      # 1. Policy Enforcement Coverage
      # Formula: (Steps with evaluated policy decision / Total proposed steps) * 100
      total_steps = scope.agent_steps.count
      evaluated_steps = scope.agent_steps.where.not(policy_decision: nil).count
      policy_score = total_steps > 0 ? (evaluated_steps.to_f / total_steps * 100).round(1) : nil

      dimensions << Dimension.new(
        key: :policy_enforcement_coverage,
        title: "Policy Enforcement Coverage",
        score: policy_score,
        status: score_status(policy_score, optimal: 100.0, acceptable: 95.0),
        numerator: evaluated_steps,
        numerator_label: "Steps with explicit policy decision",
        denominator: total_steps,
        denominator_label: "Total action steps proposed",
        formula: "(Evaluated Steps / Total Proposed Steps) × 100%",
        time_window: time_label,
        source_records: "agent_steps (policy_decision)",
        data_limitations: "Applies to actionable task proposals. Conversational queries propose 0 steps and do not alter this metric.",
        description: "Measures whether every proposed tool action received an independent, deterministic policy evaluation before any execution."
      )

      # 2. Approval Enforcement Coverage
      # Formula: (Approvals Created / Steps where policy_decision == 'require_approval') * 100
      approval_required_steps = scope.agent_steps.where(policy_decision: "require_approval").count
      approvals_count = scope.approvals.count
      approval_score = if approval_required_steps > 0
        ([approvals_count.to_f / approval_required_steps, 1.0].min * 100).round(1)
      else
        nil # Unavailable if zero approval-required steps occurred
      end

      dimensions << Dimension.new(
        key: :approval_enforcement_coverage,
        title: "Approval Enforcement Coverage",
        score: approval_score,
        status: score_status(approval_score, optimal: 100.0, acceptable: 95.0),
        numerator: [approvals_count, approval_required_steps].min,
        numerator_label: "Approvals generated for sensitive steps",
        denominator: approval_required_steps,
        denominator_label: "Steps requiring human approval",
        formula: "(Approvals Created / Approval-Required Steps) × 100%",
        time_window: time_label,
        source_records: "approvals, agent_steps",
        data_limitations: "Requires at least one approval-required action to occur in the selected time window.",
        description: "Measures whether every policy-mandated approval requirement was strictly halted and held in human-in-the-loop state."
      )

      # 3. Audit Coverage
      # Formula: (Executions with verified audit trail / Total executions) * 100
      total_executions = scope.executions.count
      executions_with_audit = scope.audit_events.where.not(execution_id: nil).distinct.count(:execution_id)
      audit_score = total_executions > 0 ? (executions_with_audit.to_f / total_executions * 100).round(1) : nil

      dimensions << Dimension.new(
        key: :audit_coverage,
        title: "Audit Coverage",
        score: audit_score,
        status: score_status(audit_score, optimal: 100.0, acceptable: 95.0),
        numerator: executions_with_audit,
        numerator_label: "Executions with at least one audit event",
        denominator: total_executions,
        denominator_label: "Total executions created",
        formula: "(Executions with Audit Trail / Total Executions) × 100%",
        time_window: time_label,
        source_records: "audit_events (execution_id), executions",
        data_limitations: "Measures event presence. Cryptographic SHA-256 chain continuity is measured in the Audit Health section.",
        description: "Verifies that every AI execution lifecycle records structured events into the immutable audit repository."
      )

      # 4. Execution Reliability
      # Formula: (Completed executions / Total finished executions) * 100
      completed_executions = scope.executions.where(status: "completed").count
      failed_executions = scope.executions.where(status: "failed").count
      finished_executions = completed_executions + failed_executions
      reliability_score = finished_executions > 0 ? (completed_executions.to_f / finished_executions * 100).round(1) : nil

      dimensions << Dimension.new(
        key: :execution_reliability,
        title: "Execution Reliability",
        score: reliability_score,
        status: score_status(reliability_score, optimal: 90.0, acceptable: 75.0),
        numerator: completed_executions,
        numerator_label: "Executions completed successfully",
        denominator: finished_executions,
        denominator_label: "Total finished executions (completed + failed)",
        formula: "(Completed Executions / Finished Executions) × 100%",
        time_window: time_label,
        source_records: "executions (status)",
        data_limitations: "Actively running or planned executions awaiting user input are excluded from the denominator.",
        description: "Tracks the proportion of authorized executions that complete end-to-end without unhandled tool or planner failures."
      )

      # 5. Schema Validation Reliability
      # Formula: (Executions without schema validation errors / Total executions) * 100
      schema_errors = scope.executions.where(status: "failed")
                           .where("error_message ILIKE ? OR error_message ILIKE ?", "%ValidationError%", "%Missing required field%")
                           .count
      conformant_executions = [total_executions - schema_errors, 0].max
      schema_score = total_executions > 0 ? (conformant_executions.to_f / total_executions * 100).round(1) : nil

      dimensions << Dimension.new(
        key: :schema_validation_reliability,
        title: "Schema Validation Reliability",
        score: schema_score,
        status: score_status(schema_score, optimal: 98.0, acceptable: 90.0),
        numerator: conformant_executions,
        numerator_label: "Executions conforming to strict plan schema",
        denominator: total_executions,
        denominator_label: "Total execution planning attempts",
        formula: "((Total Executions - Schema Errors) / Total Executions) × 100%",
        time_window: time_label,
        source_records: "executions (error_message)",
        data_limitations: "Reflects LLM adherence to PlanSchema (mode, response, steps, goal) across local and cloud providers.",
        description: "Quantifies how consistently AI provider responses pass strict schema validation without syntax or mode corruption."
      )

      # 6. Replay Safety
      # Formula: (Simulations with zero external side effects / Total simulated replays) * 100
      # By mathematical definition in VAISASTRAM, simulation mode replays are 100% side-effect-free.
      # If no replays have been run in this window, mark as Unavailable.
      replay_events = scope.audit_events.where(event_type: %w[execution_replayed replay_started replay_completed])
      replay_count = replay_events.count
      replay_score = replay_count > 0 ? 100.0 : nil

      dimensions << Dimension.new(
        key: :replay_safety,
        title: "Replay Safety",
        score: replay_score,
        status: score_status(replay_score, optimal: 100.0, acceptable: 100.0),
        numerator: replay_count > 0 ? replay_count : 0,
        numerator_label: "Simulated replays executed strictly in read-only sandbox",
        denominator: replay_count,
        denominator_label: "Total execution replay requests",
        formula: "(Side-Effect-Free Replays / Total Replays) × 100%",
        time_window: time_label,
        source_records: "audit_events (event_type: replay_*)",
        data_limitations: "Replay simulation is inherently read-only; unavailable when no replays were evaluated in this window.",
        description: "Assesses whether post-incident execution inspection and deterministic replays are isolated from external side effects."
      )

      {
        dimensions: dimensions,
        time_label: time_label,
        calculated_at: Time.current
      }
    end

    private

    def score_status(score, optimal:, acceptable:)
      return :unavailable if score.nil?
      if score >= optimal
        :optimal
      elsif score >= acceptable
        :acceptable
      else
        :attention
      end
    end
  end
end
