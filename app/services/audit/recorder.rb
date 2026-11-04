require "zlib"

module Audit
  class AuditError < StandardError; end
  class AuditPersistenceError < AuditError; end

  class Recorder
    def self.record!(**kwargs)
      new.record!(**kwargs)
    end

    def self.record(**kwargs)
      new.record(**kwargs)
    end

    def record(**kwargs)
      record!(**kwargs)
    rescue AuditPersistenceError => e
      Rails.logger.error("[VAISASTRAM Non-Critical Audit Warning] #{e.message}")
      nil
    end

    def record!(
      event_type:,
      actor_type: "system",
      actor_id: nil,
      user: nil,
      task: nil,
      execution: nil,
      agent_step: nil,
      approval: nil,
      tool_name: nil,
      action_fingerprint: nil,
      policy_decision: nil,
      status: nil,
      metadata: {},
      occurred_at: nil,
      security_critical: true
    )
      # 1. Resolve entity references
      u_id = user&.id || task&.user_id || execution&.task&.user_id
      t_id = task&.id || execution&.task_id || agent_step&.execution&.task_id || approval&.task_id
      e_id = execution&.id || agent_step&.execution_id || approval&.execution_id
      s_id = agent_step&.id || approval&.agent_step_id
      a_id = approval&.id

      t_name = tool_name.presence || agent_step&.action_key || approval&.tool_name
      a_fp = action_fingerprint.presence || approval&.action_fingerprint
      p_dec = policy_decision.presence || agent_step&.policy_decision
      stat = status.presence || agent_step&.status || execution&.status

      chain_id = Audit::EventBuilder.resolve_chain_id(execution_id: e_id, task_id: t_id)
      clean_meta = Audit::EventSchema.sanitize_metadata(metadata || {})

      # 2. Transactional persistence with advisory chain lock
      AuditEvent.transaction do
        # Acquire transaction-scoped advisory lock for this chain_id to serialize sequential entries
        lock_key = (Zlib.crc32(chain_id) & 0x7FFFFFFF)
        sanitized_sql = ActiveRecord::Base.sanitize_sql_array(["SELECT pg_advisory_xact_lock(?)", lock_key])
        ActiveRecord::Base.connection.execute(sanitized_sql)

        last_event = AuditEvent.where(chain_id: chain_id).order(sequence_number: :desc).first
        sequence_number = last_event ? last_event.sequence_number.to_i + 1 : 1
        prev_event_hash = last_event ? last_event.event_hash : Audit::EventBuilder::GENESIS_HASH

        event = AuditEvent.new(
          chain_id: chain_id,
          sequence_number: sequence_number,
          prev_event_hash: prev_event_hash,
          event_type: event_type.to_s,
          actor_type: actor_type.to_s,
          actor_id: actor_id.to_s,
          user_id: u_id,
          task_id: t_id,
          execution_id: e_id,
          agent_step_id: s_id,
          approval_id: a_id,
          tool_name: t_name,
          action_fingerprint: a_fp,
          policy_decision: p_dec,
          status: stat,
          metadata: clean_meta,
          occurred_at: occurred_at || Time.current,
          hash_version: Audit::EventBuilder::HASH_VERSION
        )

        # 3. Calculate cryptographic SHA-256 event hash
        canonical = Audit::EventBuilder.canonical_payload(event)
        event.event_hash = Audit::EventBuilder.compute_hash(canonical)

        event.save!
        event
      end
    rescue StandardError => e
      Rails.logger.error("[VAISASTRAM Audit Failure] Failed to record '#{event_type}': #{e.class} - #{e.message}")
      if security_critical
        raise AuditPersistenceError, "Security-critical audit failure for '#{event_type}': #{e.message}. Execution halted (fail-closed)."
      else
        nil
      end
    end
  end
end
