require "test_helper"

class PoliciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = users(:one)
    @admin = users(:two)
    @policy = policies(:system_allow_lookup)
    @critical_policy = policies(:system_deny_delete_financial_record)
  end

  test "redirects unauthenticated visitors to login" do
    get policies_url
    assert_redirected_to new_user_session_url
  end

  test "renders Policy Center when authenticated as operator" do
    sign_in @operator
    get policies_url

    assert_response :success
    assert_select "h1", text: /Policy Center/
    assert_select "span", text: /INDEPENDENT RUBY ENGINE/
    assert_select "div", text: /AI Proposes. Ruby Decides./
    assert_select "table"

    # Operators must NOT see toggle buttons
    assert_select "button", { text: /Disable/, count: 0 }, "Operators cannot disable policies"
    assert_select "button", { text: /Enable/, count: 0 }, "Operators cannot enable policies"
  end

  test "admin sees administrative toggle controls for non-critical policies" do
    sign_in @admin
    get policies_url

    assert_response :success
    assert_select "button", text: /Disable/
  end

  test "admin can toggle non-critical policy and creates audit event" do
    sign_in @admin
    initial_status = @policy.enabled?

    patch toggle_policy_url(@policy)

    assert_redirected_to policies_url
    follow_redirect!
    assert_response :success

    @policy.reload
    assert_equal !initial_status, @policy.enabled?

    # Verify audit event logged
    audit = AuditEvent.where(event_type: "policy_modified", actor_type: "user").last
    assert_not_nil audit
    assert_equal @admin.id, audit.user_id
    assert_equal @policy.id, audit.metadata["policy_id"]
    assert_equal @policy.enabled?, audit.metadata["enabled"]
  end

  test "admin cannot disable critical security policies" do
    sign_in @admin
    assert @critical_policy.enabled?

    patch toggle_policy_url(@critical_policy)

    assert_redirected_to policies_url
    follow_redirect!
    assert_response :success
    assert_select "div", text: /Critical security policy/

    assert @critical_policy.reload.enabled?, "Critical policy must remain enabled"
  end

  test "operator cannot toggle policies" do
    sign_in @operator
    initial_status = @policy.enabled?

    patch toggle_policy_url(@policy)

    assert_redirected_to policies_url
    follow_redirect!
    assert_select "div", text: /Only administrators can modify security policies/

    assert_equal initial_status, @policy.reload.enabled?
  end
end
