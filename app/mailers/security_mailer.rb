class SecurityMailer < ApplicationMailer
  def policy_blocked(step: nil, execution: nil, reason: nil, policy_id: nil, decision: nil, **_kwargs)
    @step = step
    @execution = execution || step&.execution
    @task = @execution&.task
    @recipient = @task&.user || User.where(role: "admin").first
    @action_key = step&.action_key || "unknown_action"
    @reason = reason.presence || decision&.reason || step&.result&.dig("error") || "Prohibited by governing policy rules"
    @policy_id = policy_id.presence || decision&.policy_id
    @blocked_at = Time.current
    @notification_type = "policy_blocked"
    @idempotency_key = "SecurityMailer:policy_blocked:#{step&.id || execution&.id}:#{@action_key}"

    mail(
      to: @recipient.email,
      subject: "[Policy Guard] Action Prohibited: #{@action_key}"
    )
  end

  def security_alert(user, details: {}, **_kwargs)
    @user = user
    @recipient = user
    @details = sanitize_details(details)
    @occurred_at = Time.current
    @notification_type = "security_alert"
    @idempotency_key = "SecurityMailer:security_alert:#{@user.id}:#{Digest::SHA256.hexdigest(@details.to_json)}"

    mail(
      to: @user.email,
      subject: "[Security Alert] Governance & Compliance Notice"
    )
  end

  def account_security_notification(user, details: {}, **_kwargs)
    @user = user
    @recipient = user
    @details = sanitize_details(details)
    @occurred_at = Time.current
    @notification_type = "account_security_notification"
    @idempotency_key = "SecurityMailer:account_security_notification:#{@user.id}:#{Digest::SHA256.hexdigest(@details.to_json)}"

    mail(
      to: @user.email,
      subject: "[Security Alert] Important Account Activity"
    )
  end

  private

  def sanitize_details(details)
    return {} unless details.is_a?(Hash)
    Audit::EventSchema.sanitize_metadata(details)
  end
end
