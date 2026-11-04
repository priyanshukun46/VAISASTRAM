class ApprovalMailer < ApplicationMailer
  def approval_required(approval, recipient: nil, **_kwargs)
    @approval = approval
    @task = approval.effective_task
    @execution = approval.effective_execution
    @recipient = recipient || approval.reviewer || approval.effective_user
    @tool_name = approval.effective_tool_name
    @arguments_summary = sanitize_arguments(approval.effective_arguments)
    @expires_at = approval.expires_at
    @notification_type = "approval_required"
    @idempotency_key = "ApprovalMailer:approval_required:#{approval.id}:#{@recipient.id}:#{approval.action_fingerprint}"

    mail(
      to: @recipient.email,
      subject: "[Action Required] Approval Requested: #{@tool_name} (Task ##{@task&.id})"
    )
  end

  def approval_approved(approval, **_kwargs)
    @approval = approval
    @task = approval.effective_task
    @execution = approval.effective_execution
    @recipient = approval.effective_user
    @tool_name = approval.effective_tool_name
    @reviewer = approval.reviewer
    @reviewed_at = approval.reviewed_at || Time.current
    @notification_type = "approval_approved"
    @idempotency_key = "ApprovalMailer:approval_approved:#{approval.id}:#{approval.reviewed_at.to_i}"

    mail(
      to: @recipient.email,
      subject: "[Approved] Action Cleared: #{@tool_name} (Task ##{@task&.id})"
    )
  end

  def approval_rejected(approval, reason: nil, **_kwargs)
    @approval = approval
    @task = approval.effective_task
    @execution = approval.effective_execution
    @recipient = approval.effective_user
    @tool_name = approval.effective_tool_name
    @reviewer = approval.reviewer
    @reason = reason.presence || approval.rejection_reason || "Policy/compliance guidelines not met"
    @reviewed_at = approval.reviewed_at || Time.current
    @notification_type = "approval_rejected"
    @idempotency_key = "ApprovalMailer:approval_rejected:#{approval.id}:#{approval.reviewed_at.to_i}"

    mail(
      to: @recipient.email,
      subject: "[Rejected] Action Denied: #{@tool_name} (Task ##{@task&.id})"
    )
  end

  private

  def sanitize_arguments(args)
    return {} unless args.is_a?(Hash)
    Audit::EventSchema.sanitize_metadata(args)
  end
end
