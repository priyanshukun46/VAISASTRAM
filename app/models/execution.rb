class Execution < ApplicationRecord
  STATUSES = %w[pending planning planned running completed failed paused blocked].freeze
  PROVIDERS = %w[gemini groq].freeze

  belongs_to :task
  belongs_to :agent
  has_one :user, through: :task
  has_many :agent_steps, -> { order(position: :asc) }, dependent: :destroy
  has_many :audit_events, dependent: :nullify

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
end
