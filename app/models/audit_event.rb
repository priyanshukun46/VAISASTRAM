class AuditEvent < ApplicationRecord
  ACTOR_TYPES = %w[user agent policy_engine system].freeze

  belongs_to :user, optional: true
  belongs_to :execution, optional: true
  belongs_to :agent_step, optional: true
  belongs_to :approval, optional: true

  before_validation :set_occurred_at, on: :create

  # Enforce append-only immutability at application level
  before_update { raise ActiveRecord::ReadOnlyRecord, "Audit events are immutable and cannot be updated." }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Audit events are immutable and cannot be deleted." }

  validates :event_type, presence: true
  validates :actor_type, presence: true, inclusion: { in: ACTOR_TYPES }
  validates :occurred_at, presence: true

  scope :chronological, -> { order(occurred_at: :asc) }
  scope :recent, -> { order(occurred_at: :desc) }
  scope :by_actor, ->(actor) { where(actor_type: actor) }
  scope :by_event, ->(type) { where(event_type: type) }

  def readonly?
    persisted?
  end

  private

  def set_occurred_at
    self.occurred_at ||= Time.current
  end
end
