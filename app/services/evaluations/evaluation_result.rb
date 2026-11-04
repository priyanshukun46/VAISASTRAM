module Evaluations
  class EvaluationResult
    attr_reader :test_case_id, :test_case_name, :category, :expected_result,
                :actual_result, :passed, :execution_timestamp, :relevant_references,
                :failure_explanation

    def initialize(
      test_case_id:,
      test_case_name:,
      category:,
      expected_result:,
      actual_result:,
      passed:,
      execution_timestamp: Time.current,
      relevant_references: {},
      failure_explanation: nil
    )
      @test_case_id = test_case_id
      @test_case_name = test_case_name
      @category = category.to_s.downcase.to_sym
      @expected_result = expected_result
      @actual_result = actual_result
      @passed = passed
      @execution_timestamp = execution_timestamp
      @relevant_references = relevant_references || {}
      @failure_explanation = failure_explanation
    end

    def passed?
      @passed == true
    end

    def failed?
      !passed?
    end

    def status_label
      passed? ? "PASS" : "FAIL"
    end
  end
end
