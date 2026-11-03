module Policies
  module Rules
    class PaymentLimitRule < BaseRule
      PAYMENT_ACTIONS = %w[prepare_payment disburse_payment process_payment].freeze
      MAX_PAYMENT_PAISE = 1_000_000 # ₹10,000.00 in integer paise

      def initialize
        super(
          rule_id: "payment_limit_rule",
          name: "Payment Spending Ceiling & Approval Guard",
          description: "Enforces currency-safe thresholds: <= ₹10k requires human approval; > ₹10k is hard denied.",
          priority: 25
        )
      end

      def evaluate(context)
        return nil unless PAYMENT_ACTIONS.include?(context.action_key)

        # 1. Guard against missing or malformed payment amounts
        # Handles Test 8 (Malformed arguments) and Test 9 (String amount manipulation)
        if context.amount_validation_error.present?
          return Decision.deny(
            policy_id: rule_id,
            reason: "Payment amount rejected: #{context.amount_validation_error}",
            matched_conditions: { valid_numeric: false, error: context.amount_validation_error },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        unless context.valid_amount?
          return Decision.deny(
            policy_id: rule_id,
            reason: "Payment amount is missing or malformed",
            matched_conditions: { valid_numeric: false },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        amount_paise = context.amount_paise
        formatted_rupees = format_rupees(amount_paise)

        # 2. Strict integer paise comparisons
        if amount_paise > MAX_PAYMENT_PAISE
          # Test 5: Payment above threshold denied
          Decision.deny(
            policy_id: rule_id,
            reason: "Payment amount ₹#{formatted_rupees} exceeds maximum allowable ceiling of ₹10,000",
            matched_conditions: { amount_paise: amount_paise, ceiling_paise: MAX_PAYMENT_PAISE, comparison: "gt" },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        else
          # Test 4: Payment below or equal to threshold requires human approval
          Decision.require_approval(
            policy_id: rule_id,
            reason: "Payment amount ₹#{formatted_rupees} requires human operator approval prior to disbursement",
            matched_conditions: { amount_paise: amount_paise, ceiling_paise: MAX_PAYMENT_PAISE, comparison: "lte" },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end
      end

      private

      def format_rupees(paise)
        if paise % 100 == 0
          (paise / 100).to_s
        else
          sprintf("%.2f", paise / 100.0)
        end
      end
    end
  end
end
