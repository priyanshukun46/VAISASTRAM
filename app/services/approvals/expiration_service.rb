module Approvals
  class ExpirationService
    DEFAULT_EXPIRATION_PERIOD = 30.minutes

    def self.default_expiration_period
      DEFAULT_EXPIRATION_PERIOD
    end

    def self.expire_stale!
      new.expire_stale!
    end

    def self.expire_single!(approval)
      new.expire_single!(approval)
    end

    def expire_stale!
      stale_approvals = Approval.where(status: "pending").where("expires_at <= ?", Time.current)
      expired_count = 0

      stale_approvals.find_each do |approval|
        if expire_single!(approval)
          expired_count += 1
        end
      end

      expired_count
    end

    def expire_single!(approval)
      Approval.transaction do
        approval.lock!
        return false unless approval.status == "pending" && approval.expires_at.present? && approval.expires_at <= Time.current

        approval.update!(status: "expired")

        if approval.agent_step.present? && approval.agent_step.status == "waiting_approval"
          approval.agent_step.update_columns(
            status: "failed",
            result: { "error" => "Approval request expired at #{approval.expires_at.iso8601}" }
          )
        end

        execution = approval.effective_execution
        if execution.present? && execution.status == "paused"
          execution.update_columns(
            status: "failed",
            error_message: "Execution halted: approval expired"
          )
        end

        record_expiration_audit!(approval)
        true
      end
    rescue StandardError => e
      Rails.logger.error("[VAISASTRAM ExpirationService Error] Approval ##{approval.id}: #{e.message}")
      false
    end

    private

    def record_expiration_audit!(approval)
      Audit::Recorder.record!(
        user: approval.effective_user,
        task: approval.effective_task,
        execution: approval.effective_execution,
        agent_step: approval.agent_step,
        approval: approval,
        event_type: "approval_expired",
        actor_type: "system",
        actor_id: "expiration_service",
        tool_name: approval.effective_tool_name,
        action_fingerprint: approval.action_fingerprint,
        status: "expired",
        occurred_at: Time.current,
        security_critical: true,
        metadata: {
          approval_id: approval.id,
          tool_name: approval.effective_tool_name,
          action_fingerprint: approval.action_fingerprint,
          expires_at: approval.expires_at&.iso8601,
          expired_at: Time.current.iso8601,
          reason: "Approval window elapsed without human review"
        }
      )
    rescue StandardError => e
      Rails.logger.error("[VAISASTRAM Audit Error] Failed to log approval_expired: #{e.message}")
    end
  end
end
