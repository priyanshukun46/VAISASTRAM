require "test_helper"

class NotificationsDispatcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Notifications::Dispatcher.enabled_in_test = true
    @user = users(:one)
    @execution = executions(:invoice_execution)
    @approval = approvals(:pending_payment_approval)
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    Notifications::Dispatcher.enabled_in_test = false
  end

  test "respects user preferences: skips optional execution notification when preference is disabled" do
    @user.update!(notification_preferences: {
      "approval_requests" => true,
      "execution_updates" => false,
      "security_alerts" => true,
      "account_notifications" => true
    })

    assert_no_enqueued_jobs only: NotificationDeliveryJob do
      Notifications::Dispatcher.dispatch(:execution_started, execution: @execution)
    end

    skipped_event = AuditEvent.where(event_type: "notification_skipped").last
    assert skipped_event
    assert_equal "user_preference_disabled", skipped_event.metadata["reason"]
    assert_equal "execution_started", skipped_event.metadata["notification_type"]
  end

  test "enqueues optional notification when user preference is enabled" do
    @user.update!(notification_preferences: {
      "approval_requests" => true,
      "execution_updates" => true,
      "security_alerts" => true,
      "account_notifications" => true
    })

    assert_enqueued_jobs 1, only: NotificationDeliveryJob do
      Notifications::Dispatcher.dispatch(:execution_started, execution: @execution)
    end

    queued_event = AuditEvent.where(event_type: "notification_queued").last
    assert queued_event
    assert_equal "execution_started", queued_event.metadata["notification_type"]
  end

  test "security-critical notifications are NEVER disabled by user preferences" do
    # User attempts to disable all notification categories
    @user.update!(notification_preferences: {
      "approval_requests" => false,
      "execution_updates" => false,
      "security_alerts" => false,
      "account_notifications" => false
    })

    # Password reset is security-critical
    assert_enqueued_jobs 1, only: NotificationDeliveryJob do
      Notifications::Dispatcher.dispatch(:password_reset, user: @user, token: "reset_token_123")
    end

    # Account security notification is security-critical
    assert_enqueued_jobs 1, only: NotificationDeliveryJob do
      Notifications::Dispatcher.dispatch(:account_security_notification, user: @user, details: { event: "Suspicious login" })
    end
  end

  test "approval emails include secure links to approval page without approving directly" do
    admin = users(:two) # eligible approver
    perform_enqueued_jobs do
      Notifications::Dispatcher.dispatch(:approval_required, approval: @approval, recipient: admin)
    end

    delivered = ActionMailer::Base.deliveries.last
    assert delivered
    assert_equal [admin.email], delivered.to
    assert_match "/approvals/#{@approval.id}", delivered.text_part.body.decoded

    # Verify that sending the email did NOT change the approval status
    @approval.reload
    assert_equal "pending", @approval.status
    assert_nil @approval.reviewed_at
  end
end
