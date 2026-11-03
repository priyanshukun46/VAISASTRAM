module Audit
  class IntegrityVerifier
    class VerificationResult
      attr_reader :valid, :chain_id, :total_events, :verified_count,
                  :tampered_event_ids, :broken_link_event_ids, :missing_sequences, :errors

      def initialize(chain_id:, total_events: 0)
        @chain_id = chain_id
        @total_events = total_events
        @verified_count = 0
        @tampered_event_ids = []
        @broken_link_event_ids = []
        @missing_sequences = []
        @errors = []
        @valid = true
      end

      def add_verified
        @verified_count += 1
      end

      def add_tamper(event_id, message)
        @tampered_event_ids << event_id
        @errors << "Tampered event ##{event_id}: #{message}"
        @valid = false
      end

      def add_broken_link(event_id, message)
        @broken_link_event_ids << event_id
        @errors << "Broken hash link at event ##{event_id}: #{message}"
        @valid = false
      end

      def add_sequence_error(expected, actual)
        @missing_sequences << expected
        @errors << "Sequence discontinuity: expected #{expected}, got #{actual}"
        @valid = false
      end

      def valid?
        @valid
      end
    end

    def self.verify_chain(chain_id)
      new.verify_chain(chain_id)
    end

    def self.verify_execution(execution_id)
      new.verify_chain("execution:#{execution_id}")
    end

    def self.verify_task(task_id)
      new.verify_chain("task:#{task_id}")
    end

    def self.verify_all
      chain_ids = AuditEvent.distinct.pluck(:chain_id).compact
      chain_ids.map { |cid| [cid, verify_chain(cid)] }.to_h
    end

    def verify_chain(chain_id)
      events = AuditEvent.where(chain_id: chain_id).order(sequence_number: :asc)
      result = VerificationResult.new(chain_id: chain_id, total_events: events.count)

      expected_seq = 1
      expected_prev_hash = Audit::EventBuilder::GENESIS_HASH

      events.each do |event|
        # 1. Sequence check
        if event.sequence_number != expected_seq
          result.add_sequence_error(expected_seq, event.sequence_number)
        end

        # 2. Previous hash link check
        unless ActiveSupport::SecurityUtils.secure_compare(event.prev_event_hash.to_s, expected_prev_hash.to_s)
          result.add_broken_link(
            event.id,
            "Expected prev_event_hash '#{expected_prev_hash.first(12)}...', got '#{event.prev_event_hash.to_s.first(12)}...'"
          )
        end

        # 3. Cryptographic digest recalculation & tamper check
        canonical = Audit::EventBuilder.canonical_payload(event)
        computed_hash = Audit::EventBuilder.compute_hash(canonical)

        unless ActiveSupport::SecurityUtils.secure_compare(computed_hash, event.event_hash.to_s)
          result.add_tamper(
            event.id,
            "Stored event_hash '#{event.event_hash.to_s.first(12)}...' does not match recomputed hash '#{computed_hash.first(12)}...'"
          )
        end

        result.add_verified
        expected_seq = event.sequence_number.to_i + 1
        expected_prev_hash = event.event_hash
      end

      result
    end
  end
end
