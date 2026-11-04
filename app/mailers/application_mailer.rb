class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM_ADDRESS", "no-reply@vaisastram.org") }
  layout "mailer"

  after_deliver :record_delivery_in_audit

  private

  def record_delivery_in_audit
    recipient_email = mail.to&.first
    user = @user || @recipient || User.find_by(email: recipient_email)

    task = @task
    task ||= @execution&.task if @execution.respond_to?(:task)
    task ||= @approval&.effective_task if @approval.respond_to?(:effective_task)

    execution = @execution
    execution ||= @approval&.effective_execution if @approval.respond_to?(:effective_execution)

    approval = @approval

    notification_type = @notification_type || action_name

    Audit::Recorder.record(
      event_type: "notification_sent",
      actor_type: "system",
      actor_id: "mailer",
      user: user,
      task: task,
      execution: execution,
      approval: approval,
      status: "delivered",
      metadata: {
        mailer: self.class.name,
        notification_type: notification_type.to_s,
        recipient_email: recipient_email,
        subject: mail.subject,
        provider_message_id: mail.message_id,
        idempotency_key: @idempotency_key
      }
    )
  rescue StandardError => e
    Rails.logger.error("[VAISASTRAM ApplicationMailer] Audit record error: #{e.class} - #{e.message}")
  end
end
