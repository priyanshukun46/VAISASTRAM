require "test_helper"

class NotificationPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    ActionMailer::Base.deliveries.clear
  end

  test "unauthenticated access to preferences redirects to login" do
    get notification_preferences_path
    assert_redirected_to new_user_session_path
  end

  test "authenticated user can view notification preferences and delivery history" do
    sign_in @user
    get notification_preferences_path
    assert_response :success
    assert_select "h1", "Notification Center"
    assert_select "form#preferences-form"
  end

  test "user can update notification preferences and an audit event is recorded" do
    sign_in @user

    assert_difference -> { AuditEvent.where(event_type: "notification_preference_updated").count }, 1 do
      patch notification_preferences_path, params: {
        preferences: {
          approval_requests: "1",
          execution_updates: "0",
          security_alerts: "1",
          account_notifications: "0"
        }
      }
    end

    assert_redirected_to notification_preferences_path
    @user.reload
    assert_equal true, @user.notification_preferences["approval_requests"]
    assert_equal false, @user.notification_preferences["execution_updates"]
    assert_equal true, @user.notification_preferences["security_alerts"]
    assert_equal false, @user.notification_preferences["account_notifications"]

    audit = AuditEvent.where(event_type: "notification_preference_updated").last
    assert_equal @user.id, audit.user_id
    assert_equal false, audit.metadata.dig("preferences", "execution_updates")
  end

  test "send_test_email enqueues a welcome email via Solid Queue" do
    sign_in @user

    assert_enqueued_jobs 1, only: NotificationDeliveryJob do
      post send_test_email_notification_preferences_path
    end

    assert_redirected_to notification_preferences_path
    assert_equal "Test notification enqueued via Active Job / Solid Queue.", flash[:notice]
  end

  test "verify_email with valid token verifies the user account" do
    token = @user.generate_email_verification_token!
    assert_nil @user.email_verified_at

    get verify_email_path(token: token)

    @user.reload
    assert @user.email_verified?
    assert_nil @user.email_verification_token
  end

  test "verify_email with invalid token fails safely" do
    get verify_email_path(token: "invalid_expired_token")
    assert_redirected_to new_user_session_path
    assert_equal "Email verification link is invalid or has expired.", flash[:alert]
  end
end
