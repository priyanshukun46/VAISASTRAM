class GovernanceController < ApplicationController
  before_action :authenticate_user!
  before_action :set_scope

  VALID_TABS = %w[overview policies approvals executions providers audit evaluations scorecard].freeze

  def index
    @active_tab = VALID_TABS.include?(params[:tab].to_s.downcase) ? params[:tab].to_s.downcase : "overview"

    # Always compute overview counts for top KPI cards
    @overview = Governance::OverviewMetrics.new(scope: @scope).calculate

    case @active_tab
    when "overview"
      # Additional snapshot data for overview
      @recent_executions = @scope.executions.order(created_at: :desc).limit(5).includes(:task, :agent)
      @pending_approvals = @scope.approvals.pending.order(created_at: :desc).limit(5)
    when "policies"
      @policy_analytics = Governance::PolicyAnalytics.new(scope: @scope).calculate
    when "approvals"
      @approval_analytics = Governance::ApprovalAnalytics.new(scope: @scope).calculate
    when "executions"
      @execution_analytics = Governance::ExecutionAnalytics.new(scope: @scope).calculate
    when "providers"
      @provider_analytics = Governance::ProviderAnalytics.new(scope: @scope).calculate
    when "audit"
      run_verify = params[:verify_audit] == "true"
      @audit_health = Governance::AuditHealth.new(scope: @scope).calculate(run_verification: run_verify)
    when "scorecard"
      @scorecard = Governance::Scorecard.new(scope: @scope).calculate
    when "evaluations"
      @evaluation_report = if session[:last_evaluation_report].present? && params[:rerun] != "true"
        # Recover last run if available
        Evaluations::Evaluator.run
      else
        Evaluations::Evaluator.run
      end
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def run_evaluations
    @evaluation_report = Evaluations::Evaluator.run

    respond_to do |format|
      format.html { redirect_to governance_path(tab: "evaluations", range: @scope.range), notice: "Evaluation suite completed: #{@evaluation_report.passed_count}/#{@evaluation_report.total_cases} passed." }
      format.turbo_stream
    end
  end

  def verify_audit
    @audit_health = Governance::AuditHealth.new(scope: @scope).calculate(run_verification: true)

    respond_to do |format|
      format.html { redirect_to governance_path(tab: "audit", range: @scope.range, verify_audit: "true"), notice: "Audit integrity check completed." }
      format.turbo_stream
    end
  end

  private

  def set_scope
    @scope = Governance::QueryScope.new(
      user: current_user,
      range: params[:range],
      start_date: params[:start_date],
      end_date: params[:end_date]
    )
  end
end
