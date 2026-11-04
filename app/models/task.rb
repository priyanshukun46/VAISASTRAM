class Task < ApplicationRecord
  STATUSES = %w[pending planning planned running completed failed cancelled blocked].freeze

  belongs_to :user
  belongs_to :agent
  has_many :executions, dependent: :destroy
  has_many :approvals, dependent: :destroy

  before_validation :set_submitted_at, on: :create

  validates :title, presence: true
  validates :instruction, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :submitted_at, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :planning, -> { where(status: "planning") }
  scope :planned, -> { where(status: "planned") }
  scope :active, -> { where(status: %w[pending planning planned running]) }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :blocked, -> { where(status: "blocked") }
  scope :recent, -> { order(submitted_at: :desc) }

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

  def blocked?
    status == "blocked"
  end

  private

  def set_submitted_at
    self.submitted_at ||= Time.current
  end
end
