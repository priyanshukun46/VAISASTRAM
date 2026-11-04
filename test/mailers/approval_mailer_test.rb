require "test_helper"

class ApprovalMailerTest < ActionMailer::TestCase
  setup do
    @approval = approvals(:pending_payment_approval)
    @admin = users(:two)
    ActionMailer::Base.deliveries.clear
  end

  test "approval_required includes secure link to approval page and does not approve directly" do
    email = ApprovalMailer.approval_required(@approval, recipient: @admin)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@admin.email], email.to
    assert_match "[Action Required] Approval Requested", email.subject
    assert_match "/approvals/#{@approval.id}", email.html_part.body.decoded
    assert_match "/approvals/#{@approval.id}", email.text_part.body.decoded
    assert_match "This email DOES NOT approve or execute this action", email.html_part.body.decoded
    assert_match "This email DOES NOT approve or execute this action", email.text_part.body.decoded
  end

  test "approval_approved notifies the task owner with reviewer details" do
    @approval.update!(status: "approved", reviewer: @admin, reviewed_at: Time.current)
    email = ApprovalMailer.approval_approved(@approval)

    assert_emails 1 do
      email.deliver_now
    end

    recipient = @approval.effective_user
    assert_equal [recipient.email], email.to
    assert_match "[Approved] Action Cleared", email.subject
    assert_match @admin.name, email.html_part.body.decoded
    assert_match @admin.name, email.text_part.body.decoded
    assert_match "/executions/#{@approval.effective_execution.id}/timeline", email.html_part.body.decoded
  end

  test "approval_rejected notifies task owner with sanitized rejection reason" do
    @approval.update!(status: "rejected", reviewer: @admin, reviewed_at: Time.current, rejection_reason: "High transaction risk detected")
    email = ApprovalMailer.approval_rejected(@approval, reason: "High transaction risk detected")

    assert_emails 1 do
      email.deliver_now
    end

    recipient = @approval.effective_user
    assert_equal [recipient.email], email.to
    assert_match "[Rejected] Action Denied", email.subject
    assert_match "High transaction risk detected", email.html_part.body.decoded
    assert_match "High transaction risk detected", email.text_part.body.decoded
  end
end
