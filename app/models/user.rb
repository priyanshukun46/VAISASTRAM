class User < ApplicationRecord
  # Devise modules: database_authenticatable, registerable, recoverable, rememberable, validatable, trackable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  ROLES = %w[admin operator auditor].freeze

  has_many :agents, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :executions, through: :tasks
  has_many :policies, dependent: :nullify
  has_many :audit_events, dependent: :nullify
  has_many :reviewed_approvals, class_name: "Approval", foreign_key: :reviewer_id, dependent: :nullify

  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  # Scopes & role helpers
  def admin?
    role == "admin"
  end

  def operator?
    role == "operator"
  end

  def auditor?
    role == "auditor"
  end

  # Rails authorization checks for user resource permissions
  # (kept distinct from the VAISASTRAM agent policy engine)
  def can_manage_all?
    admin?
  end

  def can_view_audit_stream?
    admin? || auditor? || operator?
  end

  def can_access?(record)
    return true if admin?
    return true if record.respond_to?(:user_id) && record.user_id == id
    return true if record.respond_to?(:user) && record.user == self
    return true if record.is_a?(Execution) && record.task&.user_id == id
    return true if record.is_a?(AgentStep) && record.execution&.task&.user_id == id
    return true if record.is_a?(Approval) && (record.reviewer_id == id || record.agent_step&.execution&.task&.user_id == id)
    false
  end

  def can_approve?(approval)
    # Admin or designated operator who is not the task creator (segregation of duties)
    if admin?
      true
    elsif operator?
      task_creator_id = approval.respond_to?(:task) ? approval.task&.user_id : approval.agent_step&.execution&.task&.user_id
      task_creator_id != id
    else
      false
    end
  end
end
