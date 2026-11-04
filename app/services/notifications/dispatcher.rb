module Notifications
  class Dispatcher
    class << self
      attr_accessor :enabled_in_test

      def dispatch(notification_type, **kwargs)
        # No email delivery in test environment unless explicitly requested (Requirement 9 & 10)
        if Rails.env.test? && !enabled_in_test
          return nil
        end

        new.dispatch(notification_type, **kwargs)
      end

      def with_enabled_in_test
        previous = enabled_in_test
        self.enabled_in_test = true
        yield
      ensure
        self.enabled_in_test = previous
      end
    end

    def dispatch(notification_type, **kwargs)
      notification_type = notification_type.to_s

      case notification_type
      when "welcome_email"
        dispatch_welcome(kwargs[:user])
      when "email_verification"
        dispatch_email_verification(kwargs[:user], kwargs[:token])
      when "password_reset"
        dispatch_password_reset(kwargs[:user], kwargs[:token])
      when "account_security_notification"
        dispatch_account_security(kwargs[:user], kwargs[:details] || {})
      when "approval_required"
        dispatch_approval_required(kwargs[:approval], kwargs[:recipient])
      when "approval_approved"
        dispatch_approval_approved(kwargs[:approval], kwargs[:reviewer])
      when "approval_rejected"
        dispatch_approval_rejected(kwargs[:approval], kwargs[:reviewer], kwargs[:reason])
      when "execution_started"
        dispatch_execution_started(kwargs[:execution])
      when "execution_completed"
        dispatch_execution_completed(kwargs[:execution])
      when "execution_failed"
        dispatch_execution_failed(kwargs[:execution], kwargs[:error])
      when "policy_blocked"
        dispatch_policy_blocked(kwargs[:agent_step] || kwargs[:step], kwargs[:execution], kwargs[:decision])
      when "security_alert"
        dispatch_security_alert(kwargs[:user], kwargs[:details] || {})
      else
        Rails.logger.warn("[VAISASTRAM Notifications] Unknown notification type: #{notification_type}")
        nil
      end
    end

    private

    def send_or_skip(recipient, notification_type, mailer_proc, record: nil)
      return if recipient.blank? || recipient.email.blank?

      task = extract_task(record)
      execution = extract_execution(record)
      approval = extract_approval(record)

      if recipient.wants_notification?(notification_type)
        Audit::Recorder.record(
          event_type: "notification_queued",
          actor_type: "system",
          actor_id: "notification_dispatcher",
          user: recipient,
          task: task,
          execution: execution,
          approval: approval,
          status: "queued",
          metadata: {
            notification_type: notification_type,
            recipient_email: recipient.email
          }
        )

        mailer_proc.call.deliver_later
      else
        Audit::Recorder.record(
          event_type: "notification_skipped",
          actor_type: "system",
          actor_id: "notification_dispatcher",
          user: recipient,
          task: task,
          execution: execution,
          approval: approval,
          status: "skipped",
          metadata: {
            notification_type: notification_type,
            recipient_email: recipient.email,
            reason: "user_preference_disabled"
          }
        )
      end
    end

    def dispatch_welcome(user)
      send_or_skip(user, "welcome_email", -> { UserMailer.welcome_email(user) }, record: user)
    end

    def dispatch_email_verification(user, token)
      token ||= user.generate_email_verification_token!
      send_or_skip(user, "email_verification", -> { UserMailer.email_verification(user, token) }, record: user)
    end

    def dispatch_password_reset(user, token)
      send_or_skip(user, "password_reset", -> { UserMailer.password_reset(user, token) }, record: user)
    end

    def dispatch_account_security(user, details)
      send_or_skip(user, "account_security_notification", -> { UserMailer.account_security_notification(user, details) }, record: user)
    end

    def dispatch_approval_required(approval, explicit_recipient = nil)
      recipients = if explicit_recipient.present?
        [explicit_recipient]
      elsif approval.reviewer.present?
        [approval.reviewer]
      else
        # Eligible approvers (admins and operators, excluding task creator for segregation of duties)
        task_user_id = approval.effective_user&.id
        User.where(role: %w[admin operator]).where.not(id: task_user_id).to_a
      end

      recipients.each do |recipient|
        send_or_skip(
          recipient,
          "approval_required",
          -> { ApprovalMailer.approval_required(approval, recipient: recipient) },
          record: approval
        )
      end
    end

    def dispatch_approval_approved(approval, reviewer = nil)
      recipient = approval.effective_user
      send_or_skip(
        recipient,
        "approval_approved",
        -> { ApprovalMailer.approval_approved(approval) },
        record: approval
      )
    end

    def dispatch_approval_rejected(approval, reviewer = nil, reason = nil)
      recipient = approval.effective_user
      send_or_skip(
        recipient,
        "approval_rejected",
        -> { ApprovalMailer.approval_rejected(approval, reason: reason) },
        record: approval
      )
    end

    def dispatch_execution_started(execution)
      recipient = execution.user || execution.task&.user
      send_or_skip(
        recipient,
        "execution_started",
        -> { ExecutionMailer.execution_started(execution) },
        record: execution
      )
    end

    def dispatch_execution_completed(execution)
      recipient = execution.user || execution.task&.user
      send_or_skip(
        recipient,
        "execution_completed",
        -> { ExecutionMailer.execution_completed(execution) },
        record: execution
      )
    end

    def dispatch_execution_failed(execution, error = nil)
      recipient = execution.user || execution.task&.user
      send_or_skip(
        recipient,
        "execution_failed",
        -> { ExecutionMailer.execution_failed(execution, error: error) },
        record: execution
      )
    end

    def dispatch_policy_blocked(step, execution, decision)
      user = step&.execution&.task&.user || execution&.task&.user
      reason = decision.respond_to?(:reason) ? decision.reason : decision.to_s
      policy_id = decision.respond_to?(:policy_id) ? decision.policy_id : nil

      send_or_skip(
        user,
        "policy_blocked",
        -> { SecurityMailer.policy_blocked(step: step, execution: execution, reason: reason, policy_id: policy_id) },
        record: step || execution
      )
    end

    def dispatch_security_alert(user, details)
      target_user = user || User.where(role: "admin").first
      send_or_skip(
        target_user,
        "security_alert",
        -> { SecurityMailer.security_alert(target_user, details: details) },
        record: target_user
      )
    end

    def extract_task(record)
      return record if record.is_a?(Task)
      return record.task if record.respond_to?(:task) && record.task.is_a?(Task)
      return record.effective_task if record.respond_to?(:effective_task) && record.effective_task.is_a?(Task)
      nil
    end

    def extract_execution(record)
      return record if record.is_a?(Execution)
      return record.execution if record.respond_to?(:execution) && record.execution.is_a?(Execution)
      return record.effective_execution if record.respond_to?(:effective_execution) && record.effective_execution.is_a?(Execution)
      nil
    end

    def extract_approval(record)
      return record if record.is_a?(Approval)
      nil
    end
  end
end
