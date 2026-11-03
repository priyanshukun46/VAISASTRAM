require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @admin = users(:two)
  end

  test "validates presence of email, name, and role" do
    user = User.new(name: nil, email: nil, role: nil)
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
    assert_includes user.errors[:name], "can't be blank"
    assert_includes user.errors[:role], "can't be blank"
  end

  test "validates role inclusion" do
    user = User.new(name: "Tester", email: "valid@example.com", password: "password123", role: "superhacker")
    assert_not user.valid?
    assert_includes user.errors[:role], "is not included in the list"

    user.role = "admin"
    assert user.valid?
    assert user.admin?
    assert_not user.operator?
  end

  test "validates email uniqueness via Devise" do
    duplicate = User.new(name: "Duplicate", email: @user.email, password: "password123", role: "operator")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "associations: has many agents, tasks, executions, policies, audit_events" do
    assert_respond_to @user, :agents
    assert_respond_to @user, :tasks
    assert_respond_to @user, :executions
    assert_respond_to @user, :policies
    assert_respond_to @user, :audit_events
    assert_respond_to @user, :reviewed_approvals
  end

  test "admin can manage all resources and access any record" do
    assert @admin.can_manage_all?
    assert @admin.can_view_audit_stream?

    mock_record = Struct.new(:user_id).new(9999)
    assert @admin.can_access?(mock_record)
  end

  test "operator can only access own tasks and related execution items" do
    assert_not @user.can_manage_all?

    own_task = tasks(:invoice_task)
    admin_task = tasks(:admin_task)

    assert @user.can_access?(own_task)
    assert_not @user.can_access?(admin_task)

    own_execution = executions(:invoice_execution)
    assert @user.can_access?(own_execution)

    own_step = agent_steps(:step_one)
    assert @user.can_access?(own_step)
  end

  test "approval segregation of duties: task creator cannot self-approve unless admin" do
    approval = approvals(:pending_payment_approval) # created for task owned by @user (one)

    # Task creator is operator @user
    assert_not @user.can_approve?(approval), "Task creator should not be allowed to self-approve sensitive actions"

    # Admin can approve
    assert @admin.can_approve?(approval)

    # Another independent operator can approve
    other_operator = User.create!(name: "Peer Reviewer", email: "peer@vaisastram.internal", password: "password123", role: "operator")
    assert other_operator.can_approve?(approval)
  end
end
