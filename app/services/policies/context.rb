require "bigdecimal"

module Policies
  class Context
    attr_reader :user, :agent, :task, :execution, :agent_step,
                :action_key, :arguments, :tool, :metadata

    def initialize(user: nil, agent: nil, task: nil, execution: nil, agent_step: nil, action_key: nil, arguments: {}, tool: nil, metadata: {})
      @user = user
      @agent = agent || task&.agent || agent_step&.execution&.agent
      @task = task || agent_step&.task || execution&.task
      @execution = execution || agent_step&.execution
      @agent_step = agent_step
      @action_key = (action_key || agent_step&.action_key).to_s.strip.downcase
      @arguments = (arguments || agent_step&.arguments || {}).deep_dup
      @tool = tool || (Tool.find_by(key: @action_key) if @action_key.present?)
      @metadata = (metadata || {}).deep_dup

      validate_amount!
    end

    def action_fingerprint
      @action_fingerprint ||= Fingerprint.generate(
        user: @user,
        task: @task,
        action_key: @action_key,
        arguments: @arguments,
        resource_id: resource_identifier
      )
    end

    def resource_identifier
      Fingerprint.extract_resource_id(@arguments)
    end

    def user_present?
      @user.present?
    end

    def tool_registered?
      @tool.present?
    end

    def tool_enabled?
      @tool.present? && @tool.enabled?
    end

    # Currency-Safe Monetary Handling
    # Validates amounts numerically and prevents string/decimal bypasses
    attr_reader :amount_paise, :amount_validation_error

    def valid_amount?
      @amount_paise.present? && @amount_validation_error.nil?
    end

    def sanitized_arguments
      Fingerprint.canonicalize_arguments(@arguments)
    end

    private

    def validate_amount!
      # Only validate amount if the arguments hash has an amount key
      # or if the action is a payment-related action
      has_amount_key = @arguments.key?("amount") || @arguments.key?(:amount)
      is_payment_action = @action_key.include?("payment") || @action_key.include?("payout") ||
                          @action_key.include?("disburse") || @action_key.include?("transfer")

      return unless has_amount_key || is_payment_action

      raw_amount = @arguments["amount"] || @arguments[:amount]

      if raw_amount.nil?
        @amount_validation_error = "Missing payment amount"
        return
      end

      # Reject any String representations of amounts (e.g. "10000", "₹10,000", "10,000.00")
      # Requirement: "Ensure payment amounts are validated numerically and cannot bypass limits through strings..."
      if raw_amount.is_a?(String)
        @amount_validation_error = "Payment amount cannot be a string representation; numeric value required"
        return
      end

      unless raw_amount.is_a?(Numeric)
        @amount_validation_error = "Payment amount must be a numeric value, got #{raw_amount.class.name}"
        return
      end

      if raw_amount.is_a?(Float) && (raw_amount.nan? || raw_amount.infinite?)
        @amount_validation_error = "Payment amount must be a finite number"
        return
      end

      if raw_amount <= 0
        @amount_validation_error = "Payment amount must be greater than zero"
        return
      end

      # Convert accurately to integer paise (1 INR = 100 paise)
      # Using BigDecimal to avoid IEEE floating point inaccuracies
      begin
        dec = BigDecimal(raw_amount.to_s)
        @amount_paise = (dec * 100).round.to_i
      rescue StandardError => e
        @amount_validation_error = "Malformed numeric payment amount: #{e.message}"
      end
    end
  end
end
