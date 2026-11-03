require "test_helper"

class AuditControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two)
    @operator = users(:one)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)

    # Clean existing execution audit events to ensure predictable chain
    AuditEvent.where(execution_id: @execution.id).delete_all
    @event1 = Audit::Recorder.record!(
      execution: @execution,
      task: @task,
      event_type: "task_started",
      actor_type: "user",
      actor_id: @operator.id.to_s,
      metadata: { "title" => "Invoice task" }
    )
    @event2 = Audit::Recorder.record!(
      execution: @execution,
      task: @task,
      event_type: "policy_evaluated",
      actor_type: "policy_engine",
      actor_id: "ruby_policy_engine",
      policy_decision: "allow",
      tool_name: "lookup_invoice",
      metadata: { "decision" => "allow" }
    )
  end

  test "Unauthenticated user is redirected to login" do
    get audit_url
    assert_redirected_to new_user_session_url

    post verify_audit_url
    assert_redirected_to new_user_session_url
  end

  test "Authenticated operator can access Audit Center" do
    sign_in @operator
    get audit_url
    assert_response :success
    assert_select "h1", text: /Audit Center/
    assert_select "td", text: /task_started/
    assert_select "td", text: /policy_evaluated/
  end

  test "Filter audit events by event_type" do
    sign_in @operator
    get audit_url(event_type: "policy_evaluated")
    assert_response :success
    assert_select "td", text: /policy_evaluated/
    assert_select "td", text: "task_started", count: 0
  end

  test "Filter audit events by tool_name" do
    sign_in @operator
    get audit_url(tool_name: "lookup_invoice")
    assert_response :success
    assert_select "td", text: /lookup_invoice/
  end

  test "Verify cryptographic hash chain via POST /audit/verify HTML" do
    sign_in @admin
    post verify_audit_url, params: { chain_id: "execution:#{@execution.id}" }
    assert_redirected_to audit_url
    follow_redirect!
    assert_select "div", text: /Verification completed: All hash links valid/
  end

  test "Verify cryptographic hash chain via POST /audit/verify Turbo Stream" do
    sign_in @admin
    post verify_audit_url, params: { chain_id: "execution:#{@execution.id}" }, as: :turbo_stream
    assert_response :success
    assert_match(/turbo-stream action="replace" target="integrity_verification_banner"/, response.body)
    assert_match(/Ledger Verification Passed/, response.body)
  end

  test "Detect tampered record during live verification" do
    # Tamper with an event in database
    ActiveRecord::Base.connection.execute("UPDATE audit_events SET event_hash = 'corrupted_hash' WHERE id = #{@event1.id}")

    sign_in @admin
    post verify_audit_url, params: { chain_id: "execution:#{@execution.id}" }, as: :turbo_stream
    assert_response :success
    assert_match(/Ledger Integrity Failure Detected/, response.body)
  end
end
