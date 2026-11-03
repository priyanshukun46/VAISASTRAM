module Policies
  class RuleMatcher
    def self.matches?(policy, context)
      return false unless policy.enabled?
      return false if policy.action_key.present? && policy.action_key != context.action_key && policy.action_key != "*"

      conditions = policy.conditions
      return true if conditions.blank? || conditions == {}

      evaluate_conditions(conditions, context)
    end

    def self.evaluate_conditions(conditions, context)
      conditions.each do |key, expected|
        case key.to_s
        when "amount_gt"
          return false unless context.valid_amount? && (context.amount_paise > (expected.to_f * 100).to_i)
        when "amount_gte"
          return false unless context.valid_amount? && (context.amount_paise >= (expected.to_f * 100).to_i)
        when "amount_lt"
          return false unless context.valid_amount? && (context.amount_paise < (expected.to_f * 100).to_i)
        when "amount_lte"
          return false unless context.valid_amount? && (context.amount_paise <= (expected.to_f * 100).to_i)
        when "user_role"
          return false unless context.user&.role == expected.to_s
        when "currency"
          actual_currency = (context.arguments["currency"] || context.arguments[:currency] || "INR").to_s.upcase
          return false unless actual_currency == expected.to_s.upcase
        when "required_permission"
          return false unless context.user&.role == "admin" || (context.user&.role == expected.to_s)
        else
          # Generic argument equality check
          actual_val = context.arguments[key.to_s] || context.arguments[key.to_sym]
          return false unless actual_val.to_s == expected.to_s
        end
      end

      true
    end
  end
end
