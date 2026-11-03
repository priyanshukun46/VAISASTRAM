require "test_helper"

class ApprovalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two)
    @operator = users(:one)
    @auditor = users(:auditor)
    @task = tasks(:invoice_task) # task created by @operator
    @approval = approvals(:pending_payment_approval)
  end

  test "Test 9: Unauthenticated user redirected to sign in" do
    get approvals_url
    assert_redirected_to new_user_session_url

    patch approve_approval_url(@approval)
    assert_redirected_to new_user_session_url

    patch reject_approval_url(@approval)
    assert_redirected_to new_user_session_url
  end

  test "Test 2: Pending approval appears in Approval Center for authenticated user" do
    sign_in @admin
    get approvals_url
    assert_response :success
    assert_select "h1", "Approval Center"
    assert_select "#approval_card_#{@approval.id}"
    assert_select "span", text: /Pending/
  end

  test "Test 3: Authorized admin can approve pending request" do
    sign_in @admin
    patch approve_approval_url(@approval)

    assert_redirected_to approvals_url
    follow_redirect!
    assert_select ".flex", text: /approved and executed/i

    @approval.reload
    assert_equal "executed", @approval.status
    assert_equal @admin, @approval.reviewer
  end

  test "Test 4 & 5: Authorized admin can reject pending request with reason" do
    sign_in @admin
    patch reject_approval_url(@approval), params: { rejection_reason: "Duplicate payment requested" }

    assert_redirected_to approvals_url
    follow_redirect!
    assert_select ".flex", text: /rejected/i

    @approval.reload
    assert_equal "rejected", @approval.status
    assert_equal "Duplicate payment requested", @approval.rejection_reason
    assert_equal @admin, @approval.reviewer
  end

  test "Test 10: Operator cannot approve task they created (Segregation of Duties)" do
    sign_in @operator # @operator is the owner of @approval.task
    patch approve_approval_url(@approval)

    assert_redirected_to approvals_url
    follow_redirect!
    assert_select ".flex", text: /Segregation of Duties/i

    @approval.reload
    assert_equal "pending", @approval.status
  end

  test "Test 10b: Auditor cannot approve pending request (read-only role)" do
    sign_in @auditor
    patch approve_approval_url(@approval)

    assert_redirected_to approvals_url
    follow_redirect!
    assert_select ".flex", text: /not authorized/i

    @approval.reload
    assert_equal "pending", @approval.status
  end

  test "Test 11: Reviewer ID cannot be spoofed via request parameters" do
    sign_in @admin
    # Attempt to spoof reviewer_id to another user
    patch approve_approval_url(@approval), params: { reviewer_id: @operator.id }

    @approval.reload
    # Reviewer must be the authenticated session user (@admin), never the param
    assert_equal @admin, @approval.reviewer
    assert_not_equal @operator, @approval.reviewer
  end

  test "Turbo stream response on approve" do
    sign_in @admin
    patch approve_approval_url(@approval), as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, %(target="approval_card_#{@approval.id}")
  end

  test "Turbo stream response on reject" do
    sign_in @admin
    patch reject_approval_url(@approval), params: { rejection_reason: "Invalid" }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, %(target="approval_card_#{@approval.id}")
  end
end
