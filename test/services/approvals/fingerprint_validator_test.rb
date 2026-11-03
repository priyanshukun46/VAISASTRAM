require "test_helper"

class FingerprintValidatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)
    @step = agent_steps(:step_two)
    @service = Approvals::Service.new
  end

  test "Test 24: valid fingerprint returns true" do
    approval = @service.create_request(
      user: @user,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    assert Approvals::FingerprintValidator.valid?(approval)
    assert Approvals::FingerprintValidator.validate!(approval)
  end

  test "Test 14: Modified arguments fail fingerprint validation" do
    approval = @service.create_request(
      user: @user,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    approval.action_arguments = { "invoice_id" => "INV-100", "amount" => 9000 }

    assert_not Approvals::FingerprintValidator.valid?(approval)
    assert_raises(Approvals::FingerprintMismatchError) do
      Approvals::FingerprintValidator.validate!(approval)
    end
  end

  test "Test 15: Modified tool name fails fingerprint validation" do
    approval = @service.create_request(
      user: @user,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    approval.tool_name = "prepare_payout"

    assert_not Approvals::FingerprintValidator.valid?(approval)
    assert_raises(Approvals::FingerprintMismatchError) do
      Approvals::FingerprintValidator.validate!(approval)
    end
  end

  test "Test 16: Changed resource ID in arguments fails fingerprint validation" do
    approval = @service.create_request(
      user: @user,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    approval.action_arguments = { "invoice_id" => "INV-999", "amount" => 5000 }

    assert_not Approvals::FingerprintValidator.valid?(approval)
    assert_raises(Approvals::FingerprintMismatchError) do
      Approvals::FingerprintValidator.validate!(approval)
    end
  end

  test "Test 17: Changed user fails fingerprint validation" do
    approval = @service.create_request(
      user: @user,
      task: @task,
      execution: @execution,
      agent_step: @step,
      action_key: "prepare_payment",
      arguments: { "invoice_id" => "INV-100", "amount" => 5000 }
    )

    other_user = users(:two)
    approval.user = other_user

    assert_not Approvals::FingerprintValidator.valid?(approval)
    assert_raises(Approvals::FingerprintMismatchError) do
      Approvals::FingerprintValidator.validate!(approval)
    end
  end

  test "Test 19: Unknown tools cannot be approved" do
    unknown_step = @execution.agent_steps.create!(
      position: 99,
      action_key: "unknown_hack_tool",
      arguments: { "foo" => "bar" },
      status: "waiting_approval",
      risk_level: "high"
    )

    approval = @service.create_request(
      user: @user,
      task: @task,
      execution: @execution,
      agent_step: unknown_step,
      action_key: "unknown_hack_tool",
      arguments: { "foo" => "bar" }
    )

    assert_raises(Approvals::PolicyRejectionError) do
      @service.approve(approval_id: approval.id, reviewer: users(:two))
    end
  end
end
