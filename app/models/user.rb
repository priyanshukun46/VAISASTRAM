class User < ApplicationRecord
  # Devise modules: database_authenticatable, registerable, recoverable, rememberable, validatable, trackable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  ROLES = %w[admin operator auditor].freeze

  DEFAULT_NOTIFICATION_PREFERENCES = {
    "approval_requests" => true,
    "execution_updates" => true,
    "security_alerts" => true,
    "account_notifications" => true
  }.freeze

  SECURITY_CRITICAL_NOTIFICATIONS = %w[
    password_reset
    reset_password_instructions
    account_security_notification
    security_alert
  ].freeze

  has_many :agents, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :executions, through: :tasks
  has_many :policies, dependent: :nullify
  has_many :audit_events, dependent: :nullify
  has_many :mcp_servers, dependent: :destroy
  has_many :reviewed_approvals, class_name: "Approval", foreign_key: :reviewer_id, dependent: :nullify

  after_create_commit :send_welcome_notification

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

  # Notification Preferences & Governance
  def notification_preferences
    raw = super
    raw = {} unless raw.is_a?(Hash)
    DEFAULT_NOTIFICATION_PREFERENCES.merge(raw)
  end

  def notification_preference?(category)
    notification_preferences.fetch(category.to_s, true) == true
  end

  def security_critical_notification?(type)
    SECURITY_CRITICAL_NOTIFICATIONS.include?(type.to_s)
  end

  def wants_notification?(type)
    # Security-critical account notifications must not be disabled by ordinary notification preferences
    return true if security_critical_notification?(type)

    case type.to_s
    when "approval_required", "approval_approved", "approval_rejected"
      notification_preference?("approval_requests")
    when "execution_started", "execution_completed", "execution_failed"
      notification_preference?("execution_updates")
    when "policy_blocked"
      notification_preference?("security_alerts")
    when "welcome_email", "email_verification"
      notification_preference?("account_notifications")
    else
      notification_preference?(type)
    end
  end

  def email_verified?
    email_verified_at.present?
  end

  def generate_email_verification_token!
    raw_token = SecureRandom.urlsafe_base64(32)
    update!(
      email_verification_token: raw_token,
      email_verification_sent_at: Time.current
    )
    raw_token
  end

  def verify_email!(token)
    return false if token.blank? || email_verification_token.blank?
    return false unless ActiveSupport::SecurityUtils.secure_compare(email_verification_token, token)
    return false if email_verification_sent_at.blank? || email_verification_sent_at < 24.hours.ago

    update!(
      email_verified_at: Time.current,
      email_verification_token: nil
    )
    true
  end

  private

  def send_welcome_notification
    return if Rails.env.test?

    Notifications::Dispatcher.dispatch(:welcome_email, user: self)
  rescue StandardError => e
    Rails.logger.error("[VAISASTRAM Welcome Email Error] #{e.class}: #{e.message}")
  end
end
