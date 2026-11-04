class EvaluationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @evaluation_report = Evaluations::Evaluator.run
    @scope = Governance::QueryScope.new(user: current_user, range: "all")
    @scorecard = Governance::Scorecard.new(scope: @scope).calculate

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total_cases: @evaluation_report.total_cases,
          passed_count: @evaluation_report.passed_count,
          failed_count: @evaluation_report.failed_count,
          pass_rate: @evaluation_report.pass_rate,
          duration_ms: @evaluation_report.duration_ms,
          results: @evaluation_report.results.map do |r|
            {
              id: r.test_case_id,
              name: r.test_case_name,
              category: r.category,
              status: r.status_label,
              expected: r.expected_result,
              actual: r.actual_result,
              references: r.relevant_references,
              failure_explanation: r.failure_explanation
            }
          end
        }
      end
    end
  end

  def run
    @scope = Governance::QueryScope.new(user: current_user, range: "all")
    @evaluation_report = Evaluations::Evaluator.run

    respond_to do |format|
      format.html { redirect_to evaluations_path, notice: "Evaluations completed: #{@evaluation_report.passed_count}/#{@evaluation_report.total_cases} passed." }
      format.turbo_stream
    end
  end
end
