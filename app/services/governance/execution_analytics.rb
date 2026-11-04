module Governance
  class ExecutionAnalytics
    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    def calculate
      executions = scope.executions
      steps = scope.agent_steps

      total_executions = executions.count
      completed_executions = executions.where(status: "completed").count
      failed_executions = executions.where(status: "failed").count

      finished_executions = completed_executions + failed_executions
      success_rate = finished_executions > 0 ? (completed_executions.to_f / finished_executions * 100).round(1) : nil
      failure_rate = finished_executions > 0 ? (failed_executions.to_f / finished_executions * 100).round(1) : nil

      # Execution Durations (in seconds)
      durations = executions.where.not(started_at: nil)
                            .where.not(completed_at: nil)
                            .limit(500)
                            .filter_map { |e| (e.completed_at - e.started_at).to_f if e.completed_at && e.started_at }
                            .select { |d| d >= 0 }

      avg_duration = durations.any? ? (durations.sum / durations.size).round(2) : nil
      median_duration = calculate_median(durations)

      # Tool / Step Analytics
      total_steps = steps.count
      completed_steps = steps.where(status: "completed").count
      failed_steps = steps.where(status: "failed").count
      blocked_steps = steps.where(status: "blocked").count

      tool_success_rate = total_steps > 0 ? (completed_steps.to_f / total_steps * 100).round(1) : nil
      tool_failure_rate = total_steps > 0 ? (failed_steps.to_f / total_steps * 100).round(1) : nil

      top_used_tools = steps.where.not(action_key: nil)
                            .group(:action_key)
                            .order("count_all desc")
                            .limit(5)
                            .count

      top_failing_tools = steps.where(status: "failed")
                               .where.not(action_key: nil)
                               .group(:action_key)
                               .order("count_all desc")
                               .limit(5)
                               .count

      avg_steps_per_execution = total_executions > 0 ? (total_steps.to_f / total_executions).round(2) : nil

      # Separate Distinct Failure Categories
      failure_breakdown = categorize_failures(executions)

      {
        total_executions: total_executions,
        completed_executions: completed_executions,
        failed_executions: failed_executions,
        success_rate: success_rate,
        failure_rate: failure_rate,
        avg_duration_seconds: avg_duration,
        formatted_avg_duration: format_duration(avg_duration),
        median_duration_seconds: median_duration,
        formatted_median_duration: format_duration(median_duration),
        total_steps: total_steps,
        completed_steps: completed_steps,
        failed_steps: failed_steps,
        blocked_steps: blocked_steps,
        tool_success_rate: tool_success_rate,
        tool_failure_rate: tool_failure_rate,
        top_used_tools: top_used_tools,
        top_failing_tools: top_failing_tools,
        avg_steps_per_execution: avg_steps_per_execution,
        failure_breakdown: failure_breakdown
      }
    end

    private

    def calculate_median(values)
      return nil if values.blank?
      sorted = values.sort
      len = sorted.length
      (len.odd? ? sorted[len / 2] : ((sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0)).round(2)
    end

    def format_duration(seconds)
      return "Unavailable" if seconds.nil? || seconds < 0
      if seconds < 60
        "#{seconds.round(2)}s"
      else
        mins = (seconds / 60).to_i
        secs = (seconds % 60).round(1)
        "#{mins}m #{secs}s"
      end
    end

    def categorize_failures(executions)
      failures = {
        planning_failures: 0,
        schema_validation_failures: 0,
        policy_denials: 0,
        approval_rejections: 0,
        tool_execution_failures: 0,
        provider_failures: 0,
        infrastructure_failures: 0
      }

      failed_scope = executions.where(status: %w[failed blocked])
      failed_scope.find_each do |execution|
        err = execution.error_message.to_s
        category = execution.error_category

        if category == "SCHEMA_VALIDATION_ERROR"
          failures[:schema_validation_failures] += 1
        elsif category == "ALL_PROVIDERS_FAILED" || category == "PROVIDER_TIMEOUT"
          failures[:provider_failures] += 1
        elsif execution.agent_steps.any? { |s| s.policy_decision == "deny" } || category == "POLICY_VIOLATION"
          failures[:policy_denials] += 1
        elsif execution.agent_steps.any? { |s| s.status == "rejected" } || execution.task&.approvals&.any?(&:rejected?)
          failures[:approval_rejections] += 1
        elsif execution.agent_steps.any? { |s| s.status == "failed" }
          failures[:tool_execution_failures] += 1
        elsif category == "PLANNING_ERROR"
          failures[:planning_failures] += 1
        else
          failures[:infrastructure_failures] += 1
        end
      end

      failures
    end
  end
end
