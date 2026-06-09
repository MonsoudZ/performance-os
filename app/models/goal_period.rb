class GoalPeriod < ApplicationRecord
  GOAL_TYPES = %w[
    build_muscle
    lose_fat
    increase_strength
    athletic_performance
    vertical_jump
    marathon
    longevity
  ].freeze

  belongs_to :user

  validates :goal_type, inclusion: { in: GOAL_TYPES }
  validates :started_on, presence: true
  validate :ends_after_start

  scope :active, -> { where(ended_on: nil) }

  private

  def ends_after_start
    return if ended_on.blank? || started_on.blank? || ended_on >= started_on

    errors.add(:ended_on, "must be on or after the start date")
  end
end
