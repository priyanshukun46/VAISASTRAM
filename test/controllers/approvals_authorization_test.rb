require "test_helper"

class ApprovalsAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @operator = users(:one) # Creator of the task for pending_payment_approval
    @admin = users(:two)    # Authorized admin
    @approval = approvals(:pending_payment_approval)
  end

  test "approval page link requires authentication" do
    get approval_path(@approval)
    assert_redirected_to new_user_session_path
  end

  test "authenticated authorized reviewer can access approval page" do
    sign_in @admin
    get approval_path(@approval)
    assert_response :success
    assert_select "h1", /Approval Request/
  end

  test "approval cannot be submitted without proper authorization" do
    # Under segregation of duties, the operator who owns the task cannot approve their own action
    sign_in @operator

    patch approve_approval_path(@approval)
    # Controller must redirect with authorization alert
    assert_redirected_to approvals_path
    assert_match(/Segregation of Duties|not authorized/i, flash[:alert])
    @approval.reload
    assert_equal "pending", @approval.status
  end

  test "approval emails contain authenticatable links that do not approve on GET" do
    sign_in @admin

    # Visiting the approval page link via GET must NEVER change the approval status
    get approval_path(@approval)
    assert_response :success

    @approval.reload
    assert_equal "pending", @approval.status
    assert_nil @approval.reviewed_at
  end
end
