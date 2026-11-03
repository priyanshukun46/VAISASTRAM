class Approval < ApplicationRecord
  STATUSES = %w[pending approved rejected expired].freeze

  belongs_to :agent_step
  belongs_to :reviewer, class_name: "User", optional: true
  has_one :execution, through: :agent_step
  has_many :audit_events, dependent: :nullify

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :action_digest, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :expired, -> { where(status: "expired") }
  scope :recent, -> { order(created_at: :desc) }

  def self.generate_digest(action_key, arguments)
    canonical = { action_key: action_key.to_s, arguments: arguments || {} }.to_json
    Digest::SHA256.hexdigest(canonical)
  end

  def pending?
    status == "pending" && !expired?
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def expired?
    status == "expired" || (expires_at.present? && expires_at <= Time.current && status == "pending")
  end

  def task
    agent_step&.execution&.task
  end
end
