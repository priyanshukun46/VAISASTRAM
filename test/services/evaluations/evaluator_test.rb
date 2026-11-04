require "test_helper"

class Evaluations::EvaluatorTest < ActiveSupport::TestCase
  test "executes all 20 canonical cases and passes with 100% success rate" do
    report = Evaluations::Evaluator.run

    assert_instance_of Evaluations::EvaluationReport, report
    assert_equal 20, report.total_cases
    assert_equal 20, report.passed_count
    assert_equal 0, report.failed_count
    assert_equal 100.0, report.pass_rate
    assert report.all_passed?
    assert report.duration_ms > 0

    # Test category summaries
    summary = report.category_summary
    assert summary.key?(:policy)
    assert summary.key?(:approval)
    assert summary.key?(:execution)

    assert_equal 8, summary[:policy][:total]
    assert_equal 8, summary[:policy][:passed]

    assert_equal 6, summary[:approval][:total]
    assert_equal 6, summary[:approval][:passed]

    assert_equal 6, summary[:execution][:total]
    assert_equal 6, summary[:execution][:passed]
  end

  test "runs in isolated transaction and leaves zero database pollution" do
    task_count_before = Task.count
    execution_count_before = Execution.count
    approval_count_before = Approval.count
    step_count_before = AgentStep.count
    audit_count_before = AuditEvent.count

    report = Evaluations::Evaluator.run
    assert report.all_passed?

    assert_equal task_count_before, Task.count, "Tasks count must not change after evaluator run"
    assert_equal execution_count_before, Execution.count, "Executions count must not change after evaluator run"
    assert_equal approval_count_before, Approval.count, "Approvals count must not change after evaluator run"
    assert_equal step_count_before, AgentStep.count, "AgentSteps count must not change after evaluator run"
    assert_equal audit_count_before, AuditEvent.count, "AuditEvents count must not change after evaluator run"
  end
end
