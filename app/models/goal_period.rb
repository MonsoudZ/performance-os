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

  include DateRanged

  belongs_to :user

  validates :goal_type, inclusion: { in: GOAL_TYPES }

  scope :active_on, ->(date) {
    where("started_on <= ? AND (ended_on IS NULL OR ended_on >= ?)", date, date)
  }
end
