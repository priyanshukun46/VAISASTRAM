module Policies
  class Evaluator
    attr_reader :rules

    def initialize(rules = nil)
      @rules = rules || default_rules
    end

    def evaluate(context)
      # Fail-closed guard: ensure context is a Policies::Context
      unless context.is_a?(Policies::Context)
        return Decision.deny(
          policy_id: "evaluator_context_error",
          reason: "Invalid evaluation context provided to policy engine",
          matched_conditions: { context_valid: false }
        )
      end

      # Safety: completely ignore any AI-provided risk level or claims of authorization
      # (Requirement: AI risk labels ignored; Ruby decides independently)

      begin
        decisions = []

        @rules.sort_by(&:priority).each do |rule|
          decision = rule.evaluate(context)
          next if decision.nil?

          decisions << decision

          # Short-circuit on critical system-level hard blocks (priority <= 1)
          if decision.denied? && rule.priority <= 1
            return decision
          end
        end

        resolve_precedence(decisions, context)
      rescue StandardError => e
        # Test 12: Policy engine failure blocks execution (fail-closed)
        Rails.logger.error("[VAISASTRAM Policy Engine Error] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")

        Decision.deny(
          policy_id: "evaluator_failure",
          reason: "Policy engine failure: #{e.message}. Action blocked under fail-closed security mandate.",
          matched_conditions: { error: e.class.name, message: e.message },
          action_fingerprint: context.action_fingerprint,
          context: context
        )
      end
    end

    private

    def default_rules
      [
        Rules::SensitiveOperationRule.new, # Priority 1: Hard block destructive actions
        Rules::UserPermissionRule.new,     # Priority 5: User authentication & roles
        Rules::ToolPermissionRule.new,     # Priority 10: Tool registration & allowlist
        Rules::PaymentLimitRule.new,       # Priority 25: Currency-safe spending ceilings
        Rules::DatabasePolicyRule.new      # Priority 50: Configured DB policies
      ]
    end

    # Deterministic Precedence Resolution:
    # 1. Any DENY overrides ALLOW and REQUIRE_APPROVAL (Test 10).
    # 2. REQUIRE_APPROVAL overrides ALLOW.
    # 3. ALLOW is only chosen if an explicit allow matched with zero denies or approval requirements.
    # 4. Fallback is DENY.
    def resolve_precedence(decisions, context)
      return default_deny_decision(context) if decisions.empty?

      # 1. Explicit DENY overrides everything
      first_deny = decisions.find(&:denied?)
      return first_deny if first_deny.present?

      # 2. REQUIRE_APPROVAL overrides ALLOW
      first_approval = decisions.find(&:requires_approval?)
      return first_approval if first_approval.present?

      # 3. Explicit ALLOW
      first_allow = decisions.find(&:allowed?)
      return first_allow if first_allow.present?

      default_deny_decision(context)
    end

    def default_deny_decision(context)
      Rules::DefaultDenyRule.new.evaluate(context)
    end
  end
end
