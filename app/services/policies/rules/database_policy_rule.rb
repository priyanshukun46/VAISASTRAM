module Policies
  module Rules
    class DatabasePolicyRule < BaseRule
      def initialize
        super(
          rule_id: "database_policy_rule",
          name: "Configured Database Policies",
          description: "Evaluates active database-backed policies matching the requested action key.",
          priority: 50
        )
      end

      def evaluate(context)
        return nil if context.action_key.blank?

        # Find enabled policies for this action key or global wildcard '*'
        # Disabled policies are ignored (Test 18: Disabled policies cannot authorize actions)
        matching_policies = Policy.enabled
                                  .where(action_key: [context.action_key, "*"])
                                  .where("user_id IS NULL OR user_id = ?", context.user&.id)
                                  .order(priority: :asc, created_at: :asc)

        matching_policies.each do |policy|
          next unless RuleMatcher.matches?(policy, context)

          case policy.effect
          when "deny"
            return Decision.deny(
              policy_id: "policy_#{policy.id}",
              reason: policy.description.presence || "Action denied by policy '#{policy.name}'",
              matched_conditions: policy.conditions,
              action_fingerprint: context.action_fingerprint,
              context: context
            )
          when "require_approval"
            return Decision.require_approval(
              policy_id: "policy_#{policy.id}",
              reason: policy.description.presence || "Action requires approval under policy '#{policy.name}'",
              matched_conditions: policy.conditions,
              action_fingerprint: context.action_fingerprint,
              context: context
            )
          when "allow"
            return Decision.allow(
              policy_id: "policy_#{policy.id}",
              reason: policy.description.presence || "Action permitted by policy '#{policy.name}'",
              matched_conditions: policy.conditions,
              action_fingerprint: context.action_fingerprint,
              context: context
            )
          end
        end

        nil
      end
    end
  end
end
