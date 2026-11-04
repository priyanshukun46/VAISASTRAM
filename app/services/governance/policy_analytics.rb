module Governance
  class PolicyAnalytics
    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    def calculate
      policy_events = scope.audit_events.where(event_type: "policy_evaluated")
      total_evaluations = policy_events.count

      allow_count = policy_events.where(policy_decision: "allow").count
      require_approval_count = policy_events.where(policy_decision: "require_approval").count
      deny_count = policy_events.where(policy_decision: "deny").count

      # Fallback to agent_steps if no audit events are present
      if total_evaluations == 0
        steps = scope.agent_steps.where.not(policy_decision: nil)
        total_evaluations = steps.count
        allow_count = steps.where(policy_decision: "allow").count
        require_approval_count = steps.where(policy_decision: "require_approval").count
        deny_count = steps.where(policy_decision: "deny").count
      end

      # Decision distribution percentages
      distribution = if total_evaluations > 0
        {
          allow_pct: (allow_count.to_f / total_evaluations * 100).round(1),
          require_approval_pct: (require_approval_count.to_f / total_evaluations * 100).round(1),
          deny_pct: (deny_count.to_f / total_evaluations * 100).round(1)
        }
      else
        { allow_pct: 0.0, require_approval_pct: 0.0, deny_pct: 0.0 }
      end

      # Most frequently denied tools
      top_denied_tools = policy_events.where(policy_decision: "deny")
                                      .where.not(tool_name: nil)
                                      .group(:tool_name)
                                      .order("count_all desc")
                                      .limit(5)
                                      .count

      if top_denied_tools.empty? && total_evaluations > 0
        top_denied_tools = scope.agent_steps.where(policy_decision: "deny")
                                            .group(:action_key)
                                            .order("count_all desc")
                                            .limit(5)
                                            .count
      end

      # Most frequently approval-required tools
      top_approval_required_tools = policy_events.where(policy_decision: "require_approval")
                                                 .where.not(tool_name: nil)
                                                 .group(:tool_name)
                                                 .order("count_all desc")
                                                 .limit(5)
                                                 .count

      if top_approval_required_tools.empty? && total_evaluations > 0
        top_approval_required_tools = scope.agent_steps.where(policy_decision: "require_approval")
                                                       .group(:action_key)
                                                       .order("count_all desc")
                                                       .limit(5)
                                                       .count
      end

      # Denial reasons extracted from metadata
      denial_reasons = extract_reasons(policy_events.where(policy_decision: "deny"))

      # Approval-required reasons extracted from metadata
      approval_required_reasons = extract_reasons(policy_events.where(policy_decision: "require_approval"))

      # Policy rules attribution from metadata/actor_id
      rules_attribution = extract_rules_attribution(policy_events)

      # Decisions over time (grouped by day)
      decisions_over_time = build_decisions_timeline(policy_events)

      {
        total_evaluations: total_evaluations,
        allow_count: allow_count,
        require_approval_count: require_approval_count,
        deny_count: deny_count,
        distribution: distribution,
        top_denied_tools: top_denied_tools,
        top_approval_required_tools: top_approval_required_tools,
        denial_reasons: denial_reasons,
        approval_required_reasons: approval_required_reasons,
        rules_attribution: rules_attribution,
        decisions_over_time: decisions_over_time
      }
    end

    private

    def extract_reasons(events_relation)
      reasons = Hash.new(0)
      events_relation.limit(100).each do |ev|
        reason = ev.metadata["reason"] || ev.metadata[:reason]
        if reason.present?
          clean_reason = reason.to_s.truncate(80)
          reasons[clean_reason] += 1
        end
      end
      reasons.sort_by { |_, count| -count }.first(5).to_h
    end

    def extract_rules_attribution(events_relation)
      attribution = Hash.new { |h, k| h[k] = { "allow" => 0, "require_approval" => 0, "deny" => 0 } }
      events_relation.limit(200).each do |ev|
        rule_id = ev.metadata["policy_id"] || ev.metadata[:policy_id] || ev.actor_id.presence || "system_default"
        decision = ev.policy_decision.to_s.downcase
        attribution[rule_id][decision] += 1 if %w[allow require_approval deny].include?(decision)
      end
      attribution
    end

    def build_decisions_timeline(events_relation)
      timeline = {}
      # Group by date
      events_relation.order(occurred_at: :asc).limit(500).each do |ev|
        date_key = ev.occurred_at.strftime("%Y-%m-%d")
        timeline[date_key] ||= { "allow" => 0, "require_approval" => 0, "deny" => 0, "total" => 0 }
        decision = ev.policy_decision.to_s.downcase
        if %w[allow require_approval deny].include?(decision)
          timeline[date_key][decision] += 1
          timeline[date_key]["total"] += 1
        end
      end
      timeline
    end
  end
end
