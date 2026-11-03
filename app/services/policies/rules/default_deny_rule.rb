module Policies
  module Rules
    class DefaultDenyRule < BaseRule
      def initialize
        super(
          rule_id: "default_deny_rule",
          name: "Default Deny Safety Baseline",
          description: "Denies any proposed action that has not been explicitly authorized by a governance rule.",
          priority: 999
        )
      end

      def evaluate(context)
        Decision.deny(
          policy_id: rule_id,
          reason: "Action '#{context.action_key.presence || 'unknown'}' is denied under default-deny policy",
          matched_conditions: { default_deny: true },
          action_fingerprint: context.action_fingerprint,
          context: context
        )
      end
    end
  end
end
