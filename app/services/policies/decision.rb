module Policies
  class Decision
    ALLOW = "allow".freeze
    REQUIRE_APPROVAL = "require_approval".freeze
    DENY = "deny".freeze

    DECISIONS = [ALLOW, REQUIRE_APPROVAL, DENY].freeze

    attr_reader :decision, :policy_id, :reason, :matched_conditions,
                :evaluation_timestamp, :action_fingerprint, :context

    def initialize(decision:, policy_id:, reason:, matched_conditions: {}, evaluation_timestamp: nil, action_fingerprint: nil, context: nil)
      unless DECISIONS.include?(decision.to_s.downcase)
        raise ArgumentError, "Invalid policy decision: #{decision}. Allowed: #{DECISIONS.join(', ')}"
      end

      @decision = decision.to_s.downcase.freeze
      @policy_id = policy_id.to_s.freeze
      @reason = reason.to_s.freeze
      @matched_conditions = (matched_conditions || {}).freeze
      @evaluation_timestamp = evaluation_timestamp || Time.current
      @action_fingerprint = action_fingerprint.to_s.freeze
      @context = context
    end

    def self.allow(policy_id:, reason:, matched_conditions: {}, action_fingerprint: nil, context: nil)
      new(
        decision: ALLOW,
        policy_id: policy_id,
        reason: reason,
        matched_conditions: matched_conditions,
        action_fingerprint: action_fingerprint,
        context: context
      )
    end

    def self.require_approval(policy_id:, reason:, matched_conditions: {}, action_fingerprint: nil, context: nil)
      new(
        decision: REQUIRE_APPROVAL,
        policy_id: policy_id,
        reason: reason,
        matched_conditions: matched_conditions,
        action_fingerprint: action_fingerprint,
        context: context
      )
    end

    def self.deny(policy_id:, reason:, matched_conditions: {}, action_fingerprint: nil, context: nil)
      new(
        decision: DENY,
        policy_id: policy_id,
        reason: reason,
        matched_conditions: matched_conditions,
        action_fingerprint: action_fingerprint,
        context: context
      )
    end

    def allowed?
      decision == ALLOW
    end

    def requires_approval?
      decision == REQUIRE_APPROVAL
    end

    def denied?
      decision == DENY
    end

    alias_method :blocked?, :denied?

    def to_h
      {
        decision: decision,
        policy_id: policy_id,
        reason: reason,
        matched_conditions: matched_conditions,
        evaluation_timestamp: evaluation_timestamp.iso8601,
        action_fingerprint: action_fingerprint
      }
    end

    def to_s
      "[#{decision.upcase}] Rule '#{policy_id}': #{reason} (Fingerprint: #{action_fingerprint.first(10)}...)"
    end
  end
end
