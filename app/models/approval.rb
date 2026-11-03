class Approval < ApplicationRecord
  STATUSES = %w[pending approved rejected expired invalidated executed failed].freeze

  belongs_to :user, optional: true
  belongs_to :task, optional: true
  belongs_to :execution, optional: true
  belongs_to :agent_step, optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  has_many :audit_events, dependent: :nullify

  before_validation :sync_context_and_fingerprint

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :action_digest, presence: true
  validates :action_fingerprint, presence: true
  validate :must_have_target_step_or_context

  def must_have_target_step_or_context
    if agent_step_id.blank? && task_id.blank? && user_id.blank?
      errors.add(:agent_step, :required, message: "must exist")
    end
  end

  scope :pending, -> { where(status: "pending").where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :expired, -> { where("status = 'expired' OR (status = 'pending' AND expires_at <= ?)", Time.current) }
  scope :invalidated, -> { where(status: "invalidated") }
  scope :executed, -> { where(status: "executed") }
  scope :failed, -> { where(status: "failed") }
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

  def invalidated?
    status == "invalidated"
  end

  def executed?
    status == "executed"
  end

  def failed?
    status == "failed"
  end

  def decided?
    !pending?
  end

  def effective_task
    task || agent_step&.execution&.task
  end

  def effective_execution
    execution || agent_step&.execution
  end

  def effective_user
    user || effective_task&.user
  end

  def effective_tool_name
    tool_name.presence || agent_step&.action_key
  end

  def effective_arguments
    action_arguments.presence || agent_step&.arguments || {}
  end

  def recalculate_fingerprint
    Policies::Fingerprint.generate(
      user: effective_user,
      task: effective_task,
      action_key: effective_tool_name,
      arguments: effective_arguments
    )
  end

  def matches_fingerprint?
    current_fp = recalculate_fingerprint
    return false if current_fp.blank?

    (action_fingerprint.present? && current_fp == action_fingerprint) ||
      (action_digest.present? && current_fp == action_digest)
  end

  private

  def sync_context_and_fingerprint
    # Backfill relational references from step if missing
    if agent_step.present?
      self.execution ||= agent_step.execution
      self.task ||= agent_step.execution&.task
      self.user ||= agent_step.execution&.task&.user
      self.tool_name ||= agent_step.action_key
      self.action_arguments = agent_step.arguments if action_arguments.blank? && agent_step.arguments.present?
    end

    if action_fingerprint.present? && action_digest.blank?
      self.action_digest = action_fingerprint
    elsif action_digest.present? && action_fingerprint.blank?
      self.action_fingerprint = action_digest
    end

    if action_fingerprint.blank? && effective_tool_name.present?
      computed = recalculate_fingerprint
      self.action_fingerprint = computed
      self.action_digest ||= computed
    end

    self.requested_at ||= created_at || Time.current
  end
end
