class Execution < ApplicationRecord
  STATUSES = %w[pending planning planned running completed failed paused blocked].freeze
  PROVIDERS = %w[ollama gemini groq].freeze

  belongs_to :task
  belongs_to :agent
  has_one :user, through: :task
  has_many :agent_steps, -> { order(position: :asc) }, dependent: :destroy
  has_many :audit_events, dependent: :nullify

  alias_attribute :provider_name, :provider

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :provider, presence: true
  validates :ai_model, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :planning, -> { where(status: "planning") }
  scope :planned, -> { where(status: "planned") }
  scope :running, -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :paused, -> { where(status: "paused") }
  scope :blocked, -> { where(status: "blocked") }
  scope :recent, -> { order(created_at: :desc) }

  def user_id
    task&.user_id
  end

  def pending?
    status == "pending"
  end

  def planning?
    status == "planning"
  end

  def planned?
    status == "planned"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def paused?
    status == "paused"
  end

  def blocked?
    status == "blocked"
  end

  def ai_response_text
    return nil if failed?
    plan["response"].presence || plan["summary"].presence
  end

  def error_category
    return nil unless failed?

    msg = error_message.to_s
    if msg.include?("All AI providers failed") || msg.include?("AllProvidersFailed")
      "ALL_PROVIDERS_FAILED"
    elsif msg.include?("timed out") || msg.include?("Timeout")
      "PROVIDER_TIMEOUT"
    elsif msg.include?("ValidationError") || msg.include?("Missing required field") || msg.include?("invalid type") || msg.include?("not valid JSON") || msg.include?("Invalid mode")
      "SCHEMA_VALIDATION_ERROR"
    elsif msg.include?("Authentication") || msg.include?("401") || msg.include?("403")
      "AUTHENTICATION_ERROR"
    elsif msg.include?("Rate limit") || msg.include?("429")
      "RATE_LIMIT_ERROR"
    elsif msg.include?("Malicious") || msg.include?("falsely implies")
      "POLICY_VIOLATION"
    else
      "PLANNING_ERROR"
    end
  end

  def mode
    plan["mode"] || (agent_steps.any? ? "action_plan" : "conversation")
  end

  def conversation?
    mode == "conversation"
  end

  def action_plan?
    mode == "action_plan"
  end

  def requires_action?
    return false if conversation?
    plan["requires_action"] == true || agent_steps.any?
  end

  def clarification_needed?
    plan["clarification_needed"].present?
  end

  def clarification_needed
    plan["clarification_needed"]
  end

  def explanation_text
    plan["explanation"].presence
  end

  def local_inference?
    provider == "ollama"
  end

  def cloud_inference?
    %w[gemini groq].include?(provider)
  end

  def provider_badge_label
    if fallback_used?
      "CLOUD FALLBACK — #{provider.upcase}"
    elsif local_inference?
      "LOCAL AI — #{ai_model.upcase}"
    else
      "CLOUD AI — #{provider.upcase}"
    end
  end
end
