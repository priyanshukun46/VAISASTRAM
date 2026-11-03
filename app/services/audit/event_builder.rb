require "digest"

module Audit
  class EventBuilder
    GENESIS_HASH = "GENESIS_0000000000000000000000000000000000000000000000000000000000000000".freeze
    HASH_VERSION = "v1".freeze

    def self.resolve_chain_id(execution_id: nil, task_id: nil)
      if execution_id.present?
        "execution:#{execution_id}"
      elsif task_id.present?
        "task:#{task_id}"
      else
        "system:global"
      end
    end

    def self.canonical_payload(event)
      meta = event.metadata.is_a?(Hash) ? Audit::EventSchema.sanitize_metadata(event.metadata) : {}

      {
        "chain_id" => event.chain_id.to_s,
        "sequence_number" => event.sequence_number.to_i,
        "prev_event_hash" => event.prev_event_hash.to_s,
        "event_type" => event.event_type.to_s,
        "actor_type" => event.actor_type.to_s,
        "actor_id" => event.actor_id.to_s,
        "user_id" => event.user_id,
        "task_id" => event.task_id,
        "execution_id" => event.execution_id,
        "agent_step_id" => event.agent_step_id,
        "approval_id" => event.approval_id,
        "tool_name" => event.tool_name.to_s,
        "action_fingerprint" => event.action_fingerprint.to_s,
        "policy_decision" => event.policy_decision.to_s,
        "status" => event.status.to_s,
        "hash_version" => event.hash_version.presence || HASH_VERSION,
        "metadata" => canonical_sort(meta)
      }
    end

    def self.compute_hash(payload)
      json_str = canonical_json(payload)
      Digest::SHA256.hexdigest(json_str)
    end

    def self.canonical_json(object)
      case object
      when Hash
        "{" + object.sort.map { |k, v| "#{k.to_s.to_json}:#{canonical_json(v)}" }.join(",") + "}"
      when Array
        "[" + object.map { |v| canonical_json(v) }.join(",") + "]"
      else
        object.to_json
      end
    end

    def self.canonical_sort(object)
      case object
      when Hash
        object.sort.to_h.transform_values { |v| canonical_sort(v) }
      when Array
        object.map { |v| canonical_sort(v) }
      else
        object
      end
    end
  end
end
