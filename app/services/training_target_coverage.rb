# Which exercises in a user's workouts have no training target on a given date.
#
# A template exercise without one still logs, and nothing about the logger says
# otherwise — but `DoubleProgressionEvaluator` skips any exercise it cannot find
# a prescription for, so no decision is ever written for that lift, and
# `WorkoutLogPrefill` falls back to the heaviest working set last time. The lift
# quietly stops progressing and starts repeating, which is the one failure this
# app is supposed to make impossible to miss.
#
# Answered for every template at once: the templates page asks about all of
# them, and one query for the whole set beats one per workout.
class TrainingTargetCoverage
  def initialize(user, on: user.local_date)
    @user = user
    @on = on
  end

  # The exercises on this template that no active target covers, in the order
  # they are performed.
  def uncovered_in(template)
    template.workout_template_exercises
      .sort_by(&:position)
      .map(&:exercise)
      .reject { |exercise| covered_exercise_ids.include?(exercise.id) }
  end

  def covers?(exercise)
    covered_exercise_ids.include?(exercise.id)
  end

  private

  attr_reader :user, :on

  def covered_exercise_ids
    @covered_exercise_ids ||= user.exercise_prescriptions.active_on(on).pluck(:exercise_id).to_set
  end
end
