class NotificationDeliveryJob < ActionMailer::MailDeliveryJob
  queue_as :default

  # Retry handling for temporary delivery failures
  retry_on Net::SMTPServerBusy,
           Net::SMTPUnknownError,
           Errno::ECONNRESET,
           Errno::ETIMEDOUT,
           Errno::ECONNREFUSED,
           Timeout::Error,
           SocketError,
           wait: :polynomially_longer,
           attempts: 5

  # Discard if records were removed before delivery
  discard_on ActiveJob::DeserializationError

  def perform(mailer, mail_method, delivery_method, args:, kwargs: nil, params: nil)
    idempotency_key = generate_idempotency_key(mailer, mail_method, args, kwargs, params)

    # Avoid duplicate notifications when jobs are retried
    if idempotency_key.present? && already_delivered?(idempotency_key)
      recipient_user = resolve_recipient_user(args, kwargs, params)
      Audit::Recorder.record(
        event_type: "notification_skipped",
        actor_type: "system",
        actor_id: "notification_delivery_job",
        user: recipient_user,
        status: "skipped",
        metadata: {
          notification_type: mail_method.to_s,
          reason: "duplicate_prevented",
          idempotency_key: idempotency_key
        }
      )
      return
    end

    super
  rescue StandardError => e
    # Record delivery failure in existing audit system without leaking credentials or secrets
    recipient_user = resolve_recipient_user(args, kwargs, params)
    record_delivery_failure(mailer, mail_method, recipient_user, e, idempotency_key, args)
    raise e
  end

  private

  def already_delivered?(key)
    return false if key.blank?
    AuditEvent.where(event_type: "notification_sent").where("metadata->>'idempotency_key' = ?", key.to_s).exists?
  end

  def generate_idempotency_key(mailer, mail_method, args, kwargs, params)
    if kwargs.is_a?(Hash) && (explicit = kwargs[:idempotency_key] || kwargs["idempotency_key"]).present?
      return explicit.to_s
    end
    if params.is_a?(Hash) && (explicit = params[:idempotency_key] || params["idempotency_key"]).present?
      return explicit.to_s
    end

    parts = [mailer.to_s, mail_method.to_s]
    args.each do |arg|
      if arg.respond_to?(:id)
        fingerprint = arg.respond_to?(:action_fingerprint) ? arg.action_fingerprint : nil
        parts << "#{arg.class.name}:#{arg.id}:#{fingerprint}"
      elsif arg.is_a?(Hash)
        parts << Digest::SHA256.hexdigest(arg.to_json)
      else
        parts << arg.to_s
      end
    end
    parts.join(":")
  end

  def resolve_recipient_user(args, kwargs, params)
    first_arg = args.first
    return first_arg if first_arg.is_a?(User)
    return first_arg.user if first_arg.respond_to?(:user) && first_arg.user.is_a?(User)
    return first_arg.effective_user if first_arg.respond_to?(:effective_user) && first_arg.effective_user.is_a?(User)
    return first_arg.task.user if first_arg.respond_to?(:task) && first_arg.task&.user.is_a?(User)

    if kwargs.is_a?(Hash) && kwargs[:recipient].is_a?(User)
      return kwargs[:recipient]
    end

    if params.is_a?(Hash) && params[:user].is_a?(User)
      return params[:user]
    end

    nil
  end

  def record_delivery_failure(mailer, mail_method, recipient_user, error, idempotency_key, args)
    target = args.first
    task = target if target.is_a?(Task)
    task ||= target.task if target.respond_to?(:task) && target.task.is_a?(Task)
    task ||= target.effective_task if target.respond_to?(:effective_task) && target.effective_task.is_a?(Task)

    execution = target if target.is_a?(Execution)
    execution ||= target.execution if target.respond_to?(:execution) && target.execution.is_a?(Execution)
    execution ||= target.effective_execution if target.respond_to?(:effective_execution) && target.effective_execution.is_a?(Execution)

    approval = target if target.is_a?(Approval)

    # Sanitize error message to prevent leaking internal tokens, secrets, or SMTP passwords
    clean_error = error.message.to_s
      .gsub(/password=[^&\s]+/i, "password=[REDACTED]")
      .gsub(/key=[^&\s]+/i, "key=[REDACTED]")
      .gsub(/token=[^&\s]+/i, "token=[REDACTED]")
      .truncate(250)

    Audit::Recorder.record(
      event_type: "notification_failed",
      actor_type: "system",
      actor_id: "notification_delivery_job",
      user: recipient_user,
      task: task,
      execution: execution,
      approval: approval,
      status: "failed",
      metadata: {
        mailer: mailer.to_s,
        notification_type: mail_method.to_s,
        recipient_email: recipient_user&.email,
        error_class: error.class.name,
        error_message: clean_error,
        idempotency_key: idempotency_key
      }
    )
  end
end
