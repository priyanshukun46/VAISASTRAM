module Policies
  module Rules
    class SensitiveOperationRule < BaseRule
      PROHIBITED_ACTIONS = %w[
        delete_financial_record delete_records wipe_database execute_shell drop_table truncate_records
      ].freeze

      def initialize
        super(
          rule_id: "sensitive_operation_rule",
          name: "Sensitive Operation Prohibition Guard",
          description: "Enforces hard blocks against destructive financial, database, and OS mutations.",
          priority: 1
        )
      end

      def evaluate(context)
        if PROHIBITED_ACTIONS.include?(context.action_key)
          return Decision.deny(
            policy_id: rule_id,
            reason: "Operation '#{context.action_key}' is strictly prohibited by security governance",
            matched_conditions: { prohibited_action: context.action_key },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        nil
      end
    end
  end
end
