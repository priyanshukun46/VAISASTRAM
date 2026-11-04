class Tool < ApplicationRecord
  RISK_LEVELS = %w[low medium high critical].freeze

  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_.]+\z/, message: "must contain only lowercase letters, numbers, underscores, and dots" }
  validates :name, presence: true
  validates :risk_level, presence: true, inclusion: { in: RISK_LEVELS }
  validates :enabled, inclusion: { in: [true, false] }

  scope :enabled, -> { where(enabled: true) }
  scope :by_risk, ->(level) { where(risk_level: level) }

  def enabled?
    enabled == true
  end
end
