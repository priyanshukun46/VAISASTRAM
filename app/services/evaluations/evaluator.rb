module Evaluations
  class Evaluator
    def self.run
      new.run
    end

    def run
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = []

      # Run in a rolled-back transaction so mock evaluation artifacts never pollute operational data
      ActiveRecord::Base.transaction do
        EvaluationSuite.cases.each do |test_case|
          begin
            result = test_case.run
            results << result
          rescue StandardError => e
            results << EvaluationResult.new(
              test_case_id: test_case.id,
              test_case_name: test_case.name,
              category: test_case.category,
              expected_result: "Case executed cleanly",
              actual_result: "Exception: #{e.class.name} (#{e.message})",
              passed: false,
              failure_explanation: "Unhandled exception during evaluation: #{e.message}"
            )
          end
        end

        raise ActiveRecord::Rollback
      end

      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0
      EvaluationReport.new(results: results, duration_ms: duration_ms)
    end
  end
end
