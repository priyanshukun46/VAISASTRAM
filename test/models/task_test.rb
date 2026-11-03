require "test_helper"

class TaskTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @agent = agents(:financial_agent)
    @task = tasks(:invoice_task)
  end

  test "is valid with valid attributes" do
    assert @task.valid?
  end

  test "requires title, instruction, and valid status" do
    invalid_task = Task.new(title: nil, instruction: nil, status: "invalid_status", user: @user, agent: @agent)
    assert_not invalid_task.valid?
    assert_includes invalid_task.errors[:title], "can't be blank"
    assert_includes invalid_task.errors[:instruction], "can't be blank"
    assert_includes invalid_task.errors[:status], "is not included in the list"
  end

  test "automatically sets submitted_at on creation if missing" do
    new_task = Task.create!(
      user: @user,
      agent: @agent,
      title: "New Task Title",
      instruction: "Do something specific",
      status: "pending"
    )
    assert_not_nil new_task.submitted_at
  end

  test "associations: belongs to user and agent, has many executions" do
    assert_equal @user, @task.user
    assert_equal @agent, @task.agent
    assert_respond_to @task, :executions
  end

  test "status predicates and scopes" do
    assert @task.pending?
    assert_includes Task.pending, @task
    assert_includes Task.active, @task
  end
end
