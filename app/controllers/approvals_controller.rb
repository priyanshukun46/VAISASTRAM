class ApprovalsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_approval, only: [:show, :approve, :reject]

  def index
    # Clean up stale approvals on page load for fresh UI state
    Approvals::ExpirationService.expire_stale!

    @status_filter = params[:status].presence || "pending"

    base_scope = Approval.all

    @pending_count = base_scope.pending.count
    @approved_count = base_scope.where(status: %w[approved executed]).count
    @rejected_count = base_scope.where(status: "rejected").count
    @expired_count = base_scope.expired.count
    @total_count = base_scope.count

    @approvals = case @status_filter
    when "pending"
      base_scope.pending.order(created_at: :desc)
    when "approved"
      base_scope.where(status: %w[approved executed]).order(reviewed_at: :desc, updated_at: :desc)
    when "rejected"
      base_scope.where(status: "rejected").order(reviewed_at: :desc, updated_at: :desc)
    when "expired"
      base_scope.expired.order(expires_at: :desc)
    else
      base_scope.order(created_at: :desc)
    end

    @recent_audits = AuditEvent.where(
      event_type: %w[
        approval_requested approval_approved approval_rejected
        approval_expired approval_invalidated approval_consumed
        approval_execution_succeeded approval_execution_failed
      ]
    ).order(occurred_at: :desc).limit(10)
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: @approval }
    end
  end

  def approve
    # Reviewer identity is strictly taken from authenticated session
    reviewer = current_user

    unless reviewer.can_approve?(@approval)
      error_msg = if reviewer.operator? && @approval.effective_task&.user_id == reviewer.id
        "Segregation of Duties Violation: You cannot approve an action for a task you created."
      else
        "You are not authorized to approve this action."
      end

      respond_to do |format|
        format.html { redirect_to approvals_path, alert: error_msg }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flash", locals: { alert: error_msg }) }
      end
      return
    end

    decision = Approvals::Service.approve(approval_id: @approval.id, reviewer: reviewer)

    respond_to do |format|
      format.html do
        redirect_to approvals_path, notice: "Action '#{@approval.tool_name}' approved and executed successfully."
      end
      format.turbo_stream do
        @approval.reload
        render turbo_stream: [
          turbo_stream.replace("approval_card_#{@approval.id}", partial: "approvals/approval_card", locals: { approval: @approval }),
          turbo_stream.update("pending_count_badge", "#{@pending_count.to_i - 1} Pending Approvals"),
          turbo_stream.replace("flash_messages", partial: "shared/flash", locals: { notice: "Action '#{@approval.tool_name}' approved and executed." })
        ]
      end
    end
  rescue Approvals::Error, Tools::ExecutionError => e
    respond_to do |format|
      format.html { redirect_to approvals_path, alert: e.message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flash", locals: { alert: e.message })
      end
    end
  end

  def reject
    reviewer = current_user

    unless reviewer.can_approve?(@approval) || reviewer.can_access?(@approval)
      respond_to do |format|
        format.html { redirect_to approvals_path, alert: "You are not authorized to reject this request." }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flash", locals: { alert: "You are not authorized to reject this request." }) }
      end
      return
    end

    rejection_reason = params[:rejection_reason].presence || params[:reason].presence || "Rejected by #{reviewer.name}"

    decision = Approvals::Service.reject(
      approval_id: @approval.id,
      reviewer: reviewer,
      reason: rejection_reason
    )

    respond_to do |format|
      format.html do
        redirect_to approvals_path, notice: "Action '#{@approval.tool_name}' was rejected."
      end
      format.turbo_stream do
        @approval.reload
        render turbo_stream: [
          turbo_stream.replace("approval_card_#{@approval.id}", partial: "approvals/approval_card", locals: { approval: @approval }),
          turbo_stream.replace("flash_messages", partial: "shared/flash", locals: { notice: "Action '#{@approval.tool_name}' was rejected." })
        ]
      end
    end
  rescue Approvals::Error => e
    respond_to do |format|
      format.html { redirect_to approvals_path, alert: e.message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flash", locals: { alert: e.message })
      end
    end
  end

  private

  def set_approval
    @approval = Approval.find(params[:id])
  end
end
