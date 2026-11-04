require "test_helper"

class Governance::MetricsTest < ActiveSupport::TestCase
  setup do
    @admin = users(:two)
    @operator = users(:one)
    @scope = Governance::QueryScope.new(user: @admin, range: "all")
  end

  test "OverviewMetrics computes top KPIs correctly" do
    overview = Governance::OverviewMetrics.new(scope: @scope).calculate

    assert overview.key?(:total_tasks)
    assert overview.key?(:total_executions)
    assert overview.key?(:pending_approvals)
    assert overview.key?(:total_policy_decisions)
    assert overview.key?(:policy_allow_decisions)
    assert overview.key?(:policy_require_approval_decisions)
    assert overview.key?(:policy_deny_decisions)
  end

  test "PolicyAnalytics calculates decisions and distributions" do
    policy_data = Governance::PolicyAnalytics.new(scope: @scope).calculate

    assert policy_data.key?(:total_evaluations)
    assert policy_data.key?(:allow_count)
    assert policy_data.key?(:require_approval_count)
    assert policy_data.key?(:deny_count)
    assert policy_data.key?(:distribution)
    assert policy_data[:distribution].key?(:allow_pct)
    assert policy_data[:distribution].key?(:require_approval_pct)
    assert policy_data[:distribution].key?(:deny_pct)
    assert policy_data.key?(:top_denied_tools)
    assert policy_data.key?(:top_approval_required_tools)
    assert policy_data.key?(:rules_attribution)
  end

  test "ApprovalAnalytics handles zero divisions safely" do
    # Create empty scope in future range
    future_scope = Governance::QueryScope.new(
      user: @admin,
      range: "custom",
      start_date: "2099-01-01",
      end_date: "2099-01-02"
    )

    approval_data = Governance::ApprovalAnalytics.new(scope: future_scope).calculate

    assert_equal 0, approval_data[:total_all]
    assert_nil approval_data[:avg_waiting_time_seconds]
    assert_equal "Unavailable", approval_data[:formatted_avg_waiting_time]
    assert_equal 0.0, approval_data[:distribution][:approved_pct]
  end

  test "ExecutionAnalytics computes failure breakdown correctly" do
    execution_data = Governance::ExecutionAnalytics.new(scope: @scope).calculate

    assert execution_data.key?(:total_executions)
    assert execution_data.key?(:success_rate)
    assert execution_data.key?(:failure_breakdown)

    breakdown = execution_data[:failure_breakdown]
    assert breakdown.key?(:planning_failures)
    assert breakdown.key?(:schema_validation_failures)
    assert breakdown.key?(:policy_denials)
    assert breakdown.key?(:approval_rejections)
    assert breakdown.key?(:tool_execution_failures)
    assert breakdown.key?(:provider_failures)
    assert breakdown.key?(:infrastructure_failures)
  end

  test "ProviderAnalytics handles latencies and sanitizes credentials" do
    provider_data = Governance::ProviderAnalytics.new(scope: @scope).calculate

    assert provider_data.key?(:total_requests)
    assert provider_data.key?(:provider_usage)
    assert provider_data.key?(:model_usage)
    assert provider_data.key?(:fallback_count)
    assert provider_data.key?(:avg_latency_ms)
    assert provider_data.key?(:provider_statuses)

    # Verify no credential leakage in statuses
    provider_data[:provider_statuses].each_value do |status|
      refute status.key?(:api_key)
      refute status.key?(:token)
    end
  end

  test "AuditHealth computes event distributions and respects verification toggle" do
    audit_data = Governance::AuditHealth.new(scope: @scope).calculate(run_verification: false)

    assert audit_data.key?(:total_events)
    assert audit_data.key?(:events_by_type)
    assert audit_data.key?(:events_by_actor)
    assert_equal "Not verified", audit_data[:verification][:status_label]

    # Verify with verification triggered
    verified_data = Governance::AuditHealth.new(scope: @scope).calculate(run_verification: true)
    assert verified_data[:verification][:verified]
  end

  test "Scorecard marks empty metrics as Unavailable rather than 100%" do
    empty_scope = Governance::QueryScope.new(
      user: @admin,
      range: "custom",
      start_date: "2099-01-01",
      end_date: "2099-01-02"
    )

    scorecard = Governance::Scorecard.new(scope: empty_scope).calculate
    dimensions = scorecard[:dimensions]

    assert_equal 6, dimensions.size

    dimensions.each do |dim|
      # When denominator is 0, score must be nil and status :unavailable
      assert_nil dim.score, "Dimension #{dim.key} should have nil score for empty window"
      assert_equal :unavailable, dim.status, "Dimension #{dim.key} status should be :unavailable"
      assert_equal "Unavailable", dim.formatted_score, "Dimension #{dim.key} should format as Unavailable"
    end
  end

  test "Scorecard computes transparent mathematical scores when data exists" do
    scorecard = Governance::Scorecard.new(scope: @scope).calculate
    dimensions = scorecard[:dimensions]

    policy_dim = dimensions.find { |d| d.key == :policy_enforcement_coverage }
    assert policy_dim.present?
    assert_equal "(Evaluated Steps / Total Proposed Steps) × 100%", policy_dim.formula
    assert policy_dim.numerator_label.present?
    assert policy_dim.denominator_label.present?
  end
end
