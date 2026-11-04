require "test_helper"

class ExecutionMailerTest < ActionMailer::TestCase
  setup do
    @execution = executions(:invoice_execution)
    ActionMailer::Base.deliveries.clear
  end

  test "execution_started renders task and model details in html and text" do
    email = ExecutionMailer.execution_started(@execution)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@execution.task.user.email], email.to
    assert_match "[Started] Agent Execution Begun: Task ##{@execution.task.id}", email.subject
    assert_match @execution.task.title, email.html_part.body.decoded
    assert_match @execution.task.title, email.text_part.body.decoded
    assert_match "/executions/#{@execution.id}/timeline", email.html_part.body.decoded
  end

  test "execution_completed renders completion confirmation in html and text" do
    email = ExecutionMailer.execution_completed(@execution)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@execution.task.user.email], email.to
    assert_match "[Completed] Agent Execution Finished: Task ##{@execution.task.id}", email.subject
    assert_match "Cryptographically Verified", email.html_part.body.decoded
    assert_match "/executions/#{@execution.id}/timeline", email.html_part.body.decoded
  end

  test "execution_failed sanitizes errors and never leaks secrets or passwords" do
    sensitive_error = "Payment failed with password=super_secret_db_pass and token=jwt_secret_xyz123 on database connection"
    @execution.update_columns(status: "failed", error_message: sensitive_error)

    email = ExecutionMailer.execution_failed(@execution, error: sensitive_error)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@execution.task.user.email], email.to
    assert_match "[Alert] Agent Execution Failed: Task ##{@execution.task.id}", email.subject

    # Verify secrets are thoroughly redacted
    refute_match "super_secret_db_pass", email.html_part.body.decoded
    refute_match "jwt_secret_xyz123", email.html_part.body.decoded
    refute_match "super_secret_db_pass", email.text_part.body.decoded
    refute_match "jwt_secret_xyz123", email.text_part.body.decoded

    assert_match "password=[REDACTED]", email.html_part.body.decoded
    assert_match "token=[REDACTED]", email.html_part.body.decoded
  end
end
