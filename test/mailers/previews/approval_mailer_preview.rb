class ApprovalMailerPreview < ActionMailer::Preview
  def approval_required
    approval = Approval.pending.first || mock_approval
    ApprovalMailer.approval_required(approval)
  end

  def approval_approved
    approval = Approval.approved.first || mock_approval(status: "approved")
    ApprovalMailer.approval_approved(approval)
  end

  def approval_rejected
    approval = Approval.rejected.first || mock_approval(status: "rejected", reason: "Action exceeds single transaction limit.")
    ApprovalMailer.approval_rejected(approval, reason: "Action exceeds single transaction limit.")
  end

  private

  def mock_approval(status: "pending", reason: nil)
    user = User.first || User.new(name: "Demo Operator", email: "demo@vaisastram.internal", role: "operator")
    task = Task.first || Task.new(id: 42, user: user, title: "Execute quarterly cloud vendor payment")
    execution = Execution.first || Execution.new(id: 101, task: task)
    Approval.new(
      id: 999,
      user: user,
      task: task,
      execution: execution,
      tool_name: "prepare_payment",
      action_arguments: { "vendor_id" => "VEND-8812", "amount" => 12500, "currency" => "USD" },
      action_fingerprint: "a9f8e4c7b2d103984",
      status: status,
      expires_at: 24.hours.from_now,
      reviewed_at: Time.current,
      rejection_reason: reason
    )
  end
end
