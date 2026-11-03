class AuditEvent < ApplicationRecord
  ACTOR_TYPES = %w[user agent policy_engine system].freeze

  belongs_to :user, optional: true
  belongs_to :task, optional: true
  belongs_to :execution, optional: true
  belongs_to :agent_step, optional: true
  belongs_to :approval, optional: true

  before_validation :set_occurred_at, on: :create
  before_validation :assign_chain_and_hashes, on: :create

  # Enforce append-only immutability at application level
  before_update { raise ActiveRecord::ReadOnlyRecord, "Audit events are immutable and cannot be updated." }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Audit events are immutable and cannot be deleted." }

  validates :event_type, presence: true
  validates :actor_type, presence: true, inclusion: { in: ACTOR_TYPES }
  validates :occurred_at, presence: true

  scope :chronological, -> { order(occurred_at: :asc, sequence_number: :asc) }
  scope :recent, -> { order(occurred_at: :desc, sequence_number: :desc) }
  scope :by_actor, ->(actor) { where(actor_type: actor) }
  scope :by_event, ->(type) { where(event_type: type) }
  scope :for_execution, ->(exec_id) { where(execution_id: exec_id).order(sequence_number: :asc) }
  scope :for_task, ->(task_id) { where(task_id: task_id).order(sequence_number: :asc) }
  scope :by_chain, ->(chain) { where(chain_id: chain).order(sequence_number: :asc) }

  def readonly?
    persisted?
  end

  def verify_integrity
    canonical = Audit::EventBuilder.canonical_payload(self)
    computed = Audit::EventBuilder.compute_hash(canonical)
    ActiveSupport::SecurityUtils.secure_compare(computed, event_hash.to_s)
  end

  private

  def set_occurred_at
    self.occurred_at ||= Time.current
  end

  def assign_chain_and_hashes
    self.task_id ||= execution&.task_id || agent_step&.execution&.task_id || approval&.task_id
    self.user_id ||= task&.user_id || execution&.task&.user_id
    self.chain_id ||= Audit::EventBuilder.resolve_chain_id(execution_id: execution_id, task_id: task_id)
    self.hash_version ||= Audit::EventBuilder::HASH_VERSION

    # If created directly without Audit::Recorder, populate sequence and hashes
    if sequence_number.blank? || event_hash.blank?
      last_evt = AuditEvent.where(chain_id: chain_id).where.not(id: id).order(sequence_number: :desc).first
      self.sequence_number ||= last_evt ? last_evt.sequence_number.to_i + 1 : 1
      self.prev_event_hash ||= last_evt ? last_evt.event_hash : Audit::EventBuilder::GENESIS_HASH

      canonical = Audit::EventBuilder.canonical_payload(self)
      self.event_hash ||= Audit::EventBuilder.compute_hash(canonical)
    end
  end
end
