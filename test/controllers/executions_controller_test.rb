require "test_helper"

class ExecutionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two)
    @operator = users(:one)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)
    @step = agent_steps(:step_one)

    # Record valid chained events for @execution
    AuditEvent.where(execution_id: @execution.id).delete_all
    @e1 = Audit::Recorder.record!(
      execution: @execution,
      task: @task,
      event_type: "task_started",
      actor_type: "user",
      actor_id: @operator.id.to_s,
      metadata: { "title" => "Invoice processing" }
    )
    @e2 = Audit::Recorder.record!(
      execution: @execution,
      task: @task,
      agent_step: @step,
      event_type: "policy_evaluated",
      actor_type: "policy_engine",
      actor_id: "ruby_policy_engine",
      policy_decision: "allow",
      metadata: { "decision" => "allow", "tool_name" => "retrieve_invoice" }
    )
    @e3 = Audit::Recorder.record!(
      execution: @execution,
      task: @task,
      agent_step: @step,
      event_type: "tool_execution_succeeded",
      actor_type: "system",
      actor_id: "tools_executor",
      tool_name: "retrieve_invoice",
      metadata: { "tool_name" => "retrieve_invoice", "status" => "success" }
    )
  end

  test "Unauthenticated user is redirected to sign in" do
    get timeline_execution_url(@execution)
    assert_redirected_to new_user_session_url

    get replay_execution_url(@execution)
    assert_redirected_to new_user_session_url
  end

  test "Test 26: Timeline view renders all events chronologically" do
    sign_in @operator
    get timeline_execution_url(@execution)
    assert_response :success

    assert_select "h1", text: /Execution Timeline/
    assert_select "span", text: /task_started/
    assert_select "span", text: /policy_evaluated/
    assert_select "span", text: /tool_execution_succeeded/
  end

  test "Test 27: Timeline view displays policy decisions and approval status" do
    sign_in @operator
    get timeline_execution_url(@execution)
    assert_response :success

    # Policy decision badge
    assert_select "strong", text: /allow/i
  end

  test "Test 28: Timeline view shows hash chain verification status" do
    sign_in @operator
    get timeline_execution_url(@execution)
    assert_response :success

    # Cryptographic integrity badge
    assert_select "div", text: /Cryptographic Hash Chain Verified/
    assert_select "div", text: /3 verified links/
  end

  test "Test 29: Comparison view highlights policy differences between original and replay" do
    sign_in @operator
    get replay_execution_url(@execution, mode: "simulation")
    assert_response :success

    assert_select "h1", text: /Execution Replay/
    assert_select "span", text: /SIMULATION MODE/
    assert_select "span", text: "lookup_invoice"
    assert_select "span", text: "prepare_payment"
  end

  test "Test 30: Verification failure displays visual warning in UI" do
    # Tamper with an event in the chain directly in database via raw SQL
    ActiveRecord::Base.connection.execute("UPDATE audit_events SET metadata = '{\"decision\": \"tampered\"}' WHERE id = #{@e2.id}")

    sign_in @operator
    get timeline_execution_url(@execution)
    assert_response :success

    assert_select "div", text: /Integrity Violations Detected/
  end

  test "Unauthorized user is blocked from accessing execution timeline" do
    outsider = User.create!(
      name: "Outsider",
      email: "outsider_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "operator"
    )
    sign_in outsider

    get timeline_execution_url(@execution)
    assert_redirected_to workspace_url
    follow_redirect!
    assert_select "div", text: /You are not authorized to view Execution/
  end

  test "Audit view renders raw audit logs for execution" do
    sign_in @operator
    get audit_execution_url(@execution)
    assert_response :success
    assert_select "h1", text: /Execution Audit Records/
    assert_select "td", text: /task_started/
  end
end
