require "test_helper"

class ResumptionIntegrationTest < ActiveSupport::TestCase
  setup do
    @admin = users(:two)
    @operator = users(:one)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)
    @step_one = agent_steps(:step_one)
    @step_two = agent_steps(:step_two)
  end

  test "Test 26: Existing ALLOW actions still execute normally through Executor" do
    result = Tools::Executor.execute(step: @step_one, user: @operator)

    assert result.success?
    @step_one.reload
    assert_equal "completed", @step_one.status
    assert_equal "allow", @step_one.policy_decision
    assert_equal "retrieved", @step_one.result["status"]
  end

  test "Test 27: Existing DENY actions remain blocked" do
    deny_step = @execution.agent_steps.create!(
      position: 10,
      action_key: "delete_financial_record",
      arguments: { "target" => "INV-100" },
      status: "pending",
      risk_level: "critical"
    )

    result = Tools::Executor.execute(step: deny_step, user: @operator)

    assert result.blocked?
    deny_step.reload
    assert_equal "blocked", deny_step.status
    assert_equal "deny", deny_step.policy_decision
    assert_includes deny_step.result["error"], "strictly prohibited"
  end

  test "Test 28, 29, 30: REQUIRE_APPROVAL pauses execution, approval resumes original execution, and payment remains simulated" do
    # 1. Prepare payment <= 10k triggers REQUIRE_APPROVAL and pauses execution
    result = Tools::Executor.execute(step: @step_two, user: @operator)

    assert result.paused?
    @step_two.reload
    assert_equal "waiting_approval", @step_two.status
    assert_equal "require_approval", @step_two.policy_decision

    @execution.reload
    assert_equal "paused", @execution.status

    # Approval was created
    approval = result.approval
    assert_not_nil approval
    assert_equal "pending", approval.status
    assert_equal "prepare_payment", approval.tool_name

    # 2. Reviewer signs off and approves
    decision = Approvals::Service.approve(approval_id: approval.id, reviewer: @admin)
    assert decision.success?

    # 3. Execution resumes, step completes, and payment preparation is purely simulated
    @step_two.reload
    assert_equal "completed", @step_two.status
    assert_equal "voucher_prepared", @step_two.result["status"]
    assert_match(/^VCH-[A-F0-9]{8}$/, @step_two.result["voucher_id"])
    assert_equal 5000, @step_two.result["amount"]
    assert_equal "INR", @step_two.result["currency"]

    approval.reload
    assert_equal "executed", approval.status

    @execution.reload
    assert_equal "completed", @execution.status
  end
end
