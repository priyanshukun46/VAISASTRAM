require "test_helper"

class SecurityMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    @step = agent_steps(:step_one)
    @execution = @step.execution
    ActionMailer::Base.deliveries.clear
  end

  test "policy_blocked renders prohibited action and reason in html and text" do
    decision = Struct.new(:reason, :policy_id).new("Blocked by strict data protection rule", "pol_secure_01")
    email = SecurityMailer.policy_blocked(step: @step, execution: @execution, decision: decision)

    assert_emails 1 do
      email.deliver_now
    end

    recipient = @execution.task.user
    assert_equal [recipient.email], email.to
    assert_match "[Policy Guard] Action Prohibited: #{@step.action_key}", email.subject
    assert_match "Blocked by strict data protection rule", email.html_part.body.decoded
    assert_match "Blocked by strict data protection rule", email.text_part.body.decoded
    assert_match "/policies", email.html_part.body.decoded
  end

  test "security_alert renders sanitized security anomaly details" do
    details = {
      "type" => "FINGERPRINT_TAMPERING_DETECTED",
      "message" => "Unverified action fingerprint attempted execution",
      "action_fingerprint" => "sha256_mock_hash_987",
      "secret_api_key" => "sk-live-secret-never-expose"
    }
    email = SecurityMailer.security_alert(@user, details: details)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
    assert_match "[Security Alert] Governance & Compliance Notice", email.subject
    assert_match "FINGERPRINT_TAMPERING_DETECTED", email.html_part.body.decoded
    assert_match "Unverified action fingerprint", email.html_part.body.decoded

    # Verify sensitive key was stripped by sanitizer
    refute_match "sk-live-secret-never-expose", email.html_part.body.decoded
  end

  test "account_security_notification renders critical account notice" do
    details = { "event" => "Password changed from new location" }
    email = SecurityMailer.account_security_notification(@user, details: details)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
    assert_match "[Security Alert] Important Account Activity", email.subject
    assert_match "Password changed from new location", email.html_part.body.decoded
    assert_match "Password changed from new location", email.text_part.body.decoded
  end
end
