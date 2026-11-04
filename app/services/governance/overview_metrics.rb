module Governance
  class OverviewMetrics
    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    def calculate
      tasks = scope.tasks
      executions = scope.executions
      approvals = scope.approvals
      audit_events = scope.audit_events

      # Executions metrics
      total_executions = executions.count
      successful_executions = executions.where(status: "completed").count
      failed_executions = executions.where(status: "failed").count
      running_executions = executions.where(status: %w[running planning]).count

      # Tasks metrics
      total_tasks = tasks.count
      cancelled_tasks = tasks.where(status: "cancelled").count

      # Approvals metrics
      now = Time.current
      pending_approvals = approvals.where(status: "pending").where("expires_at IS NULL OR expires_at > ?", now).count
      approved_approvals = approvals.where(status: %w[approved executed]).count
      rejected_approvals = approvals.where(status: "rejected").count
      expired_approvals = approvals.where("status = 'expired' OR (status = 'pending' AND expires_at <= ?)", now).count

      # Policy decisions metrics (from actual policy evaluations)
      policy_events = audit_events.where(event_type: "policy_evaluated")
      policy_allow = policy_events.where(policy_decision: "allow").count
      policy_require_approval = policy_events.where(policy_decision: "require_approval").count
      policy_deny = policy_events.where(policy_decision: "deny").count

      # Fallback to agent_steps if no policy_evaluated audit events exist in scope
      if policy_events.empty?
        steps = scope.agent_steps
        policy_allow = steps.where(policy_decision: "allow").count
        policy_require_approval = steps.where(policy_decision: "require_approval").count
        policy_deny = steps.where(policy_decision: "deny").count
      end

      total_policy_decisions = policy_allow + policy_require_approval + policy_deny

      {
        total_tasks: total_tasks,
        cancelled_tasks: cancelled_tasks,
        total_executions: total_executions,
        successful_executions: successful_executions,
        failed_executions: failed_executions,
        running_executions: running_executions,
        pending_approvals: pending_approvals,
        approved_approvals: approved_approvals,
        rejected_approvals: rejected_approvals,
        expired_approvals: expired_approvals,
        policy_allow_decisions: policy_allow,
        policy_require_approval_decisions: policy_require_approval,
        policy_deny_decisions: policy_deny,
        total_policy_decisions: total_policy_decisions,
        success_rate: total_executions > 0 ? (successful_executions.to_f / total_executions * 100).round(1) : nil
      }
    end
  end
end
