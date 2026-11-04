require "test_helper"

class Governance::QueryScopeTest < ActiveSupport::TestCase
  setup do
    @operator = users(:one)
    @admin = users(:two)
    @auditor = users(:auditor)
  end

  test "range parsing correctly computes time bounds" do
    scope_24h = Governance::QueryScope.new(user: @admin, range: "24h")
    assert scope_24h.start_time.present?
    assert_in_delta 24.hours.ago.to_i, scope_24h.start_time.to_i, 5
    assert_equal "Last 24 Hours", scope_24h.range_label

    scope_7d = Governance::QueryScope.new(user: @admin, range: "7d")
    assert_in_delta 7.days.ago.to_i, scope_7d.start_time.to_i, 5
    assert_equal "Last 7 Days", scope_7d.range_label

    scope_30d = Governance::QueryScope.new(user: @admin, range: "30d")
    assert_in_delta 30.days.ago.to_i, scope_30d.start_time.to_i, 5
    assert_equal "Last 30 Days", scope_30d.range_label

    scope_all = Governance::QueryScope.new(user: @admin, range: "all")
    assert_nil scope_all.start_time
    assert_nil scope_all.end_time
    assert_equal "All Time", scope_all.range_label

    scope_custom = Governance::QueryScope.new(
      user: @admin,
      range: "custom",
      start_date: "2026-01-01",
      end_date: "2026-01-10"
    )
    assert_equal Date.parse("2026-01-01").beginning_of_day, scope_custom.start_time
    assert_equal Date.parse("2026-01-10").end_of_day, scope_custom.end_time
    assert_includes scope_custom.range_label, "Jan 01, 2026"
  end

  test "admin scope has access to all records" do
    scope = Governance::QueryScope.new(user: @admin, range: "all")
    assert_equal Task.count, scope.tasks.count
    assert_equal Execution.count, scope.executions.count
    assert_equal Approval.count, scope.approvals.count
    assert_equal AuditEvent.count, scope.audit_events.count
  end

  test "auditor scope has access to all records" do
    scope = Governance::QueryScope.new(user: @auditor, range: "all")
    assert_equal Task.count, scope.tasks.count
    assert_equal Execution.count, scope.executions.count
    assert_equal Approval.count, scope.approvals.count
    assert_equal AuditEvent.count, scope.audit_events.count
  end

  test "operator scope is restricted to their own tasks, executions, and approvals" do
    operator_scope = Governance::QueryScope.new(user: @operator, range: "all")
    admin_task = tasks(:admin_task)

    # Operator should NOT see admin's task
    refute_includes operator_scope.tasks, admin_task

    # Operator should only see their own tasks
    assert operator_scope.tasks.all? { |t| t.user_id == @operator.id }

    # Operator's approvals should belong to them
    assert operator_scope.approvals.all? { |a| a.user_id == @operator.id || a.task&.user_id == @operator.id }
  end
end
