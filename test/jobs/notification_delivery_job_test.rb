require "test_helper"

class NotificationDeliveryJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
    ActionMailer::Base.deliveries.clear
  end

  test "enqueues delivery job when deliver_later is invoked" do
    assert_enqueued_jobs 1, only: NotificationDeliveryJob do
      UserMailer.welcome_email(@user).deliver_later
    end
  end

  test "delivers email and records notification_sent audit event with provider_message_id" do
    assert_difference -> { AuditEvent.where(event_type: "notification_sent").count }, 1 do
      perform_enqueued_jobs do
        UserMailer.welcome_email(@user).deliver_later
      end
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    audit = AuditEvent.where(event_type: "notification_sent").last
    assert_equal @user.id, audit.user_id
    assert_equal "delivered", audit.status
    assert audit.metadata["provider_message_id"].present?
    assert_equal @user.email, audit.metadata["recipient_email"]
  end

  test "duplicate prevention: re-running delivery job with same idempotency key suppresses duplicate email" do
    idempotency_key = "test_idempotency_unique_key_123"

    # Pre-seed a delivered notification with this idempotency key
    Audit::Recorder.record!(
      event_type: "notification_sent",
      actor_type: "system",
      actor_id: "mailer",
      user: @user,
      status: "delivered",
      metadata: {
        notification_type: "welcome_email",
        idempotency_key: idempotency_key
      }
    )

    # Now run delivery with the duplicate idempotency key
    assert_no_emails do
      NotificationDeliveryJob.perform_now(
        "UserMailer",
        "welcome_email",
        "deliver_now",
        args: [@user],
        kwargs: { idempotency_key: idempotency_key }
      )
    end

    # Verify a notification_skipped event was recorded with duplicate_prevented
    skipped_event = AuditEvent.where(event_type: "notification_skipped").last
    assert skipped_event
    assert_equal "duplicate_prevented", skipped_event.metadata["reason"]
    assert_equal idempotency_key, skipped_event.metadata["idempotency_key"]
  end

  test "failed delivery records notification_failed audit event without leaking credentials" do
    # Temporarily override welcome_email on UserMailer to simulate an SMTP failure
    UserMailer.class_eval do
      alias_method :orig_welcome_email, :welcome_email
      def welcome_email(*)
        raise Net::SMTPServerBusy, "Server busy with password=supersecret"
      end
    end

    begin
      assert_difference -> { AuditEvent.where(event_type: "notification_failed").count }, 1 do
        NotificationDeliveryJob.perform_now(
          "UserMailer",
          "welcome_email",
          "deliver_now",
          args: [@user]
        )
      end
    ensure
      UserMailer.class_eval do
        alias_method :welcome_email, :orig_welcome_email
        remove_method :orig_welcome_email
      end
    end

    failed_event = AuditEvent.where(event_type: "notification_failed").last
    assert_equal "failed", failed_event.status
    assert_equal "Net::SMTPServerBusy", failed_event.metadata["error_class"]

    # Verify password was redacted
    refute_match "supersecret", failed_event.metadata["error_message"]
    assert_match "password=[REDACTED]", failed_event.metadata["error_message"]
  end
end
