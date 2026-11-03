module Approvals
  class Decision
    attr_reader :status, :approval, :execution_result, :error_message

    def initialize(status:, approval:, execution_result: nil, error_message: nil)
      @status = status.to_s
      @approval = approval
      @execution_result = execution_result
      @error_message = error_message
    end

    def success?
      %w[approved rejected executed].include?(@status) && @error_message.blank?
    end

    def approved?
      @status == "approved" || @status == "executed"
    end

    def rejected?
      @status == "rejected"
    end

    def executed?
      @status == "executed"
    end

    def expired?
      @status == "expired"
    end

    def invalidated?
      @status == "invalidated"
    end

    def failed?
      @status == "failed"
    end
  end
end
