module Evaluations
  class EvaluationReport
    attr_reader :results, :duration_ms, :executed_at

    def initialize(results:, duration_ms:, executed_at: Time.current)
      @results = results || []
      @duration_ms = duration_ms.to_f.round(2)
      @executed_at = executed_at
    end

    def total_cases
      @results.size
    end

    def passed_count
      @results.count(&:passed?)
    end

    def failed_count
      @results.count(&:failed?)
    end

    def pass_rate
      total_cases > 0 ? (passed_count.to_f / total_cases * 100).round(1) : 0.0
    end

    def all_passed?
      failed_count == 0 && total_cases > 0
    end

    def results_by_category
      @results.group_by(&:category)
    end

    def category_summary
      results_by_category.transform_values do |cat_results|
        passed = cat_results.count(&:passed?)
        total = cat_results.size
        {
          passed: passed,
          failed: total - passed,
          total: total,
          rate: total > 0 ? (passed.to_f / total * 100).round(1) : 0.0
        }
      end
    end
  end
end
