class ExecutionMailer < ApplicationMailer
  def execution_started(execution, **_kwargs)
    @execution = execution
    @task = execution.task
    @recipient = execution.user || @task.user
    @agent = execution.agent
    @started_at = execution.started_at || Time.current
    @notification_type = "execution_started"
    @idempotency_key = "ExecutionMailer:execution_started:#{execution.id}"

    mail(
      to: @recipient.email,
      subject: "[Started] Agent Execution Begun: Task ##{@task.id}"
    )
  end

  def execution_completed(execution, **_kwargs)
    @execution = execution
    @task = execution.task
    @recipient = execution.user || @task.user
    @agent = execution.agent
    @completed_at = execution.completed_at || Time.current
    @steps_count = execution.agent_steps.count
    @notification_type = "execution_completed"
    @idempotency_key = "ExecutionMailer:execution_completed:#{execution.id}"

    mail(
      to: @recipient.email,
      subject: "[Completed] Agent Execution Finished: Task ##{@task.id}"
    )
  end

  def execution_failed(execution, error: nil, **_kwargs)
    @execution = execution
    @task = execution.task
    @recipient = execution.user || @task.user
    @agent = execution.agent
    @error_category = execution.error_category || "EXECUTION_FAILURE"
    # Never expose internal exceptions, tracebacks, database queries, or credentials in emails
    raw_error = error.presence || execution.error_message
    @sanitized_summary = sanitize_error(raw_error)
    @failed_at = Time.current
    @notification_type = "execution_failed"
    @idempotency_key = "ExecutionMailer:execution_failed:#{execution.id}"

    mail(
      to: @recipient.email,
      subject: "[Alert] Agent Execution Failed: Task ##{@task.id}"
    )
  end

  private

  def sanitize_error(raw)
    return "The agent encountered an unexpected failure during execution." if raw.blank?

    cleaned = raw.to_s
      .gsub(/password=[^&\s]+/i, "password=[REDACTED]")
      .gsub(/token=[^&\s]+/i, "token=[REDACTED]")
      .gsub(/key=[^&\s]+/i, "key=[REDACTED]")
      .gsub(/secret=[^&\s]+/i, "secret=[REDACTED]")
      .gsub(/authorization:[^\n]+/i, "Authorization: [REDACTED]")

    # Strip SQL syntax or backtraces if present
    cleaned = cleaned.split("\n").first.to_s
    cleaned.truncate(160)
  end
end
