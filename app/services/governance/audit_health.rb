module Governance
  class AuditHealth
    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    def calculate(run_verification: false)
      audit_events = scope.audit_events
      total_events = audit_events.count

      events_by_type = audit_events.group(:event_type).order("count_all desc").count
      events_by_actor = audit_events.group(:actor_type).count

      # Top executions by event count
      events_by_execution = audit_events.where.not(execution_id: nil)
                                        .group(:execution_id)
                                        .order("count_all desc")
                                        .limit(5)
                                        .count

      # Broken references: events with missing execution or task where expected
      events_missing_task = audit_events.where(task_id: nil).where.not(event_type: %w[system_startup user_registered]).count

      # Chain verification status
      verification_data = if run_verification
        perform_verification
      else
        {
          verified: false,
          status_label: "Not verified",
          last_verified_at: nil,
          verified_chains: 0,
          broken_chains_count: 0,
          tampered_events_count: 0,
          missing_sequences_count: 0,
          failed_checks: []
        }
      end

      {
        total_events: total_events,
        events_by_type: events_by_type,
        events_by_actor: events_by_actor,
        events_by_execution: events_by_execution,
        events_missing_task: events_missing_task,
        verification: verification_data
      }
    end

    def perform_verification
      chain_ids = scope.audit_events.distinct.pluck(:chain_id).compact
      return {
        verified: true,
        status_label: "Verified (Empty)",
        last_verified_at: Time.current,
        verified_chains: 0,
        broken_chains_count: 0,
        tampered_events_count: 0,
        missing_sequences_count: 0,
        failed_checks: []
      } if chain_ids.empty?

      results = chain_ids.map { |cid| Audit::IntegrityVerifier.verify_chain(cid) }

      broken_chains = results.reject(&:valid?)
      tampered_count = results.sum { |r| r.tampered_event_ids.size }
      broken_links_count = results.sum { |r| r.broken_link_event_ids.size }
      missing_sequences_count = results.sum { |r| r.missing_sequences.size }
      all_errors = results.flat_map(&:errors)

      status_label = if broken_chains.empty?
        "Verified (Intact)"
      else
        "Compromised (#{broken_chains.size} invalid chains)"
      end

      {
        verified: true,
        status_label: status_label,
        last_verified_at: Time.current,
        verified_chains: results.size,
        broken_chains_count: broken_chains.size,
        tampered_events_count: tampered_count,
        broken_links_count: broken_links_count,
        missing_sequences_count: missing_sequences_count,
        failed_checks: all_errors
      }
    end
  end
end
