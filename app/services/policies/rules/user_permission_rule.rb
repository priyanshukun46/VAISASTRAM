module Policies
  module Rules
    class UserPermissionRule < BaseRule
      def initialize
        super(
          rule_id: "user_permission_rule",
          name: "User Authentication & Permission Guard",
          description: "Ensures the action has an authenticated user with sufficient role permissions.",
          priority: 5
        )
      end

      def evaluate(context)
        # 1. Require authenticated user context
        unless context.user_present?
          return Decision.deny(
            policy_id: rule_id,
            reason: "Missing required authenticated user context",
            matched_conditions: { user_present: false },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        # 2. Check tool-level required permission if configured
        if context.tool.present? && context.tool.required_permission.present?
          req_perm = context.tool.required_permission

          # Admins have all permissions; others must match specific role capabilities
          authorized = context.user.admin? || user_satisfies_permission?(context.user, req_perm)
          unless authorized
            return Decision.deny(
              policy_id: rule_id,
              reason: "User '#{context.user.email}' (role: #{context.user.role}) lacks required permission '#{req_perm}'",
              matched_conditions: { required_permission: req_perm, user_role: context.user.role },
              action_fingerprint: context.action_fingerprint,
              context: context
            )
          end
        end

        nil
      end

      private

      def user_satisfies_permission?(user, required_permission)
        case required_permission
        when "invoice:read", "invoice:verify", "vendor:read"
          user.operator? || user.auditor?
        when "payment:prepare"
          user.operator?
        when "admin:delete_records"
          user.admin?
        else
          false
        end
      end
    end
  end
end
