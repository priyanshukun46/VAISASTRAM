require "test_helper"

class GovernanceControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @operator = users(:one)
    @admin = users(:two)
    @auditor = users(:auditor)
  end

  test "unauthenticated user is redirected to sign in" do
    get governance_path
    assert_redirected_to new_user_session_path
  end

  test "operator can access governance dashboard scoped to their tenant" do
    sign_in @operator
    get governance_path
    assert_response :success
    assert_select "h1", text: /Deterministic Governance Control Plane/
    assert_select "span", text: /Tenant: #{@operator.email}/
  end

  test "admin can access governance dashboard with system-wide scope" do
    sign_in @admin
    get governance_path
    assert_response :success
    assert_select "span", text: /System-wide \(Admin\)/
  end

  test "tab switching renders appropriate partials" do
    sign_in @admin

    %w[overview policies approvals executions providers audit evaluations scorecard].each do |tab|
      get governance_path(tab: tab)
      assert_response :success, "Failed to load tab: #{tab}"
    end
  end

  test "date filtering applies without errors" do
    sign_in @admin

    %w[24h 7d 30d all].each do |r|
      get governance_path(range: r)
      assert_response :success
    end

    get governance_path(range: "custom", start_date: "2026-01-01", end_date: "2026-01-15")
    assert_response :success
  end

  test "run_evaluations executes suite and redirects via HTML" do
    sign_in @admin
    post run_governance_evaluations_path
    assert_redirected_to governance_path(tab: "evaluations", range: "7d")
    follow_redirect!
    assert_response :success
  end

  test "run_evaluations renders turbo stream format" do
    sign_in @admin
    post run_governance_evaluations_path, as: :turbo_stream
    assert_response :success
    assert_includes response.media_type, "text/vnd.turbo-stream.html"
    assert_includes response.body, %(turbo-stream action="replace" target="evaluations_section")
  end

  test "verify_audit executes integrity verification and renders turbo stream" do
    sign_in @admin
    post verify_governance_audit_path, as: :turbo_stream
    assert_response :success
    assert_includes response.media_type, "text/vnd.turbo-stream.html"
    assert_includes response.body, %(turbo-stream action="replace" target="audit_health_section")
  end
end
