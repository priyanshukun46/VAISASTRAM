class Policy < ApplicationRecord
  EFFECTS = %w[allow deny require_approval].freeze

  belongs_to :user, optional: true

  validates :name, presence: true
  validates :action_key, presence: true
  validates :effect, presence: true, inclusion: { in: EFFECTS }
  validates :priority, presence: true, numericality: { only_integer: true }
  validates :enabled, inclusion: { in: [true, false] }

  scope :system_wide, -> { where(user_id: nil) }
  scope :user_defined, -> { where.not(user_id: nil) }
  scope :enabled, -> { where(enabled: true) }
  scope :by_priority, -> { order(priority: :asc, created_at: :asc) }

  def system_wide?
    user_id.nil?
  end

  def allow?
    effect == "allow"
  end

  def deny?
    effect == "deny"
  end

  def require_approval?
    effect == "require_approval"
  end
end
