class AgentStep < ApplicationRecord
  STATUSES = %w[pending evaluating_policy waiting_approval approved rejected running completed failed blocked].freeze
  RISK_LEVELS = %w[unknown low medium high critical].freeze
  POLICY_DECISIONS = %w[allow deny require_approval].freeze

  belongs_to :execution
  has_one :task, through: :execution
  has_many :approvals, dependent: :destroy
  has_many :audit_events, dependent: :nullify

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, uniqueness: { scope: :execution_id }
  validates :action_key, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :risk_level, presence: true, inclusion: { in: RISK_LEVELS }
  validates :policy_decision, inclusion: { in: POLICY_DECISIONS }, allow_nil: true

  scope :ordered, -> { order(position: :asc) }
  scope :pending, -> { where(status: "pending") }
  scope :waiting_approval, -> { where(status: "waiting_approval") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :blocked, -> { where(status: "blocked") }

  def waiting_approval?
    status == "waiting_approval"
  end

  def completed?
    status == "completed"
  end

  def blocked?
    status == "blocked"
  end
end
