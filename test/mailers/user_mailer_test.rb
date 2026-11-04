require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    ActionMailer::Base.deliveries.clear
  end

  test "welcome_email renders correct headers and content in html and text" do
    email = UserMailer.welcome_email(@user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
    assert_equal "Welcome to VAISASTRAM Governance Platform", email.subject
    assert_match "Welcome to VAISASTRAM, #{@user.name}!", email.html_part.body.decoded
    assert_match "Welcome to VAISASTRAM, #{@user.name}!", email.text_part.body.decoded
    assert_match @user.email, email.html_part.body.decoded
    assert_match "Launch Agent Workspace", email.html_part.body.decoded
  end

  test "email_verification renders token and secure link in html and text" do
    token = "secure_verification_token_abc123"
    email = UserMailer.email_verification(@user, token)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
    assert_equal "Verify your VAISASTRAM account email", email.subject
    assert_match token, email.html_part.body.decoded
    assert_match token, email.text_part.body.decoded
    assert_match "Verify Email Address", email.html_part.body.decoded
  end

  test "password_reset renders reset token link in html and text" do
    token = "secret_reset_token_xyz789"
    email = UserMailer.password_reset(@user, token)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
    assert_equal "Reset your VAISASTRAM password", email.subject
    assert_match token, email.html_part.body.decoded
    assert_match token, email.text_part.body.decoded
    assert_match "Reset Password", email.html_part.body.decoded
  end

  test "reset_password_instructions integrates with Devise recoverable" do
    token = "devise_token_456"
    email = UserMailer.reset_password_instructions(@user, token)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
    assert_match "Reset your VAISASTRAM password", email.subject
    assert_match token, email.html_part.body.decoded
    assert_match token, email.text_part.body.decoded
  end

  test "account_security_notification renders security details safely" do
    details = { "event" => "Suspicious login attempt", "ip_address" => "192.0.2.1" }
    email = UserMailer.account_security_notification(@user, details)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
    assert_equal "Security Alert: Important activity on your VAISASTRAM account", email.subject
    assert_match "Suspicious login attempt", email.html_part.body.decoded
    assert_match "192.0.2.1", email.html_part.body.decoded
    assert_match "Suspicious login attempt", email.text_part.body.decoded
    assert_match "192.0.2.1", email.text_part.body.decoded
  end
end
