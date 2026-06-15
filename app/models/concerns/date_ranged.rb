# A user-scoped record with an inclusive started_on/ended_on lifecycle: only one
# is active at a time, and ending one sets ended_on to the day before its
# successor opens. Shared by ExercisePrescription, GoalPeriod, and Mesocycle.
#
# `active_on` is intentionally NOT defined here — Mesocycle derives an implicit
# end from its length, so each model keeps its own.
module DateRanged
  extend ActiveSupport::Concern

  included do
    validates :started_on, presence: true
    validate :ends_after_start

    scope :active, -> { where(ended_on: nil) }
  end

  # The ended_on that retires this record the day before `pivot_date`, clamped so
  # it never precedes the start (end dates are inclusive; a record opened today
  # and ended today keeps a one-day span).
  def ended_on_for(pivot_date)
    [ pivot_date - 1.day, started_on ].max
  end

  private

  def ends_after_start
    return if ended_on.blank? || started_on.blank? || ended_on >= started_on

    errors.add(:ended_on, "must be on or after the start date")
  end
end
