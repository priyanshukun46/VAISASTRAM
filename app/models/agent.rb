class Agent < ApplicationRecord
  STATUSES = %w[active paused archived].freeze

  belongs_to :user
  has_many :tasks, dependent: :destroy
  has_many :executions, dependent: :destroy

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
  scope :paused, -> { where(status: "paused") }
  scope :archived, -> { where(status: "archived") }

  def active?
    status == "active"
  end

  def paused?
    status == "paused"
  end

  def archived?
    status == "archived"
  end
end
