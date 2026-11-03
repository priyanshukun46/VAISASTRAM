module Policies
  module Rules
    class ToolPermissionRule < BaseRule
      ALLOWLISTED_READ_ACTIONS = %w[
        retrieve_invoice lookup_invoice verify_invoice get_vendor
      ].freeze

      def initialize
        super(
          rule_id: "tool_permission_rule",
          name: "Tool Registration & Status Guard",
          description: "Verifies the requested tool is registered in VAISASTRAM and actively enabled.",
          priority: 10
        )
      end

      def evaluate(context)
        # 1. Reject unregistered tools
        unless context.tool_registered?
          return Decision.deny(
            policy_id: rule_id,
            reason: "Unknown or unregistered tool '#{context.action_key}' is denied",
            matched_conditions: { registered: false },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        # 2. Reject disabled tools
        unless context.tool_enabled?
          return Decision.deny(
            policy_id: rule_id,
            reason: "Tool '#{context.action_key}' is disabled by administrative policy",
            matched_conditions: { enabled: false },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        # 3. Explicit allow for registered read-only allowlisted tools
        if ALLOWLISTED_READ_ACTIONS.include?(context.action_key)
          return Decision.allow(
            policy_id: rule_id,
            reason: "Tool '#{context.action_key}' is registered, enabled, and allowlisted for autonomous execution",
            matched_conditions: { registered: true, enabled: true, action: context.action_key },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        nil
      end
    end
  end
end
