require "test_helper"

class EvaluationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
  end

  test "unauthenticated user is redirected to sign in" do
    get evaluations_path
    assert_redirected_to new_user_session_path
  end

  test "authenticated user can get evaluation index HTML" do
    sign_in @user
    get evaluations_path
    assert_response :success
    assert_select "h1", text: /Evaluation Center/
    assert_select "span", text: /20 Deterministic Test Cases/
  end

  test "authenticated user can get evaluation index JSON" do
    sign_in @user
    get evaluations_path, as: :json
    assert_response :success
    assert_equal "application/json", response.media_type

    json = JSON.parse(response.body)
    assert_equal 20, json["total_cases"]
    assert_equal 20, json["passed_count"]
    assert_equal 0, json["failed_count"]
    assert_equal 100.0, json["pass_rate"]
    assert_equal 20, json["results"].size
    assert json["duration_ms"] > 0
  end

  test "run action executes suite and redirects via HTML" do
    sign_in @user
    post run_evaluations_path
    assert_redirected_to evaluations_path
    follow_redirect!
    assert_response :success
  end

  test "run action renders turbo stream format" do
    sign_in @user
    post run_evaluations_path, as: :turbo_stream
    assert_response :success
    assert_includes response.media_type, "text/vnd.turbo-stream.html"
    assert_includes response.body, %(turbo-stream action="replace" target="evaluations_section")
  end
end
