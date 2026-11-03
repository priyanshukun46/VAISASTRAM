require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "redirects to sign in when unauthenticated" do
    get root_url
    assert_redirected_to new_user_session_url
  end

  test "redirects legacy /session/new to Devise sign in" do
    get "/session/new"
    assert_redirected_to new_user_session_url
  end

  test "renders dashboard when authenticated via Devise" do
    sign_in @user
    get root_url
    assert_response :success
    assert_select "h1", text: /Governance Operations Console/
    assert_select "span", text: /ENFORCING/
  end

  test "renders all top navigation pages when authenticated" do
    sign_in @user

    get workspace_url
    assert_response :success
    assert_select "h1", text: /Agent Workspace/

    get approvals_url
    assert_response :success
    assert_select "h1", text: /Approval Center/

    get policies_url
    assert_response :success
    assert_select "h1", text: /Policy Center/

    get audit_url
    assert_response :success
    assert_select "h1", text: /Audit Center/

    get evaluations_url
    assert_response :success
    assert_select "h1", text: /Evaluation Center/
  end

  test "allows login with valid credentials via Devise sessions" do
    post user_session_url, params: {
      user: {
        email: @user.email,
        password: "password123"
      }
    }
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "rejects login with invalid credentials" do
    post user_session_url, params: {
      user: {
        email: @user.email,
        password: "wrongpassword"
      }
    }
    assert_response :unprocessable_entity
  end

  test "allows user logout" do
    sign_in @user
    delete destroy_user_session_url
    assert_redirected_to root_url
  end

  test "allows new user registration with name and role" do
    assert_difference("User.count", 1) do
      post user_registration_url, params: {
        user: {
          name: "New Operator",
          email: "new_op@vaisastram.internal",
          role: "operator",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    assert_redirected_to root_url
    new_user = User.find_by(email: "new_op@vaisastram.internal")
    assert_equal "New Operator", new_user.name
    assert_equal "operator", new_user.role
  end

  test "authorize_record_access denies access to foreign records for standard operator" do
    sign_in @user # operator one
    get root_url

    foreign_record = Struct.new(:user_id).new(users(:two).id)
    assert_not @controller.can_access?(foreign_record)
  end

  test "authorize_record_access permits access to all records for admin" do
    sign_in users(:two) # admin
    get root_url

    foreign_record = Struct.new(:user_id).new(@user.id)
    assert @controller.can_access?(foreign_record)
  end
end
