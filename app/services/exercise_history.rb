# Everything the exercise detail page needs about one lift: how it has been
# trained, what it is being trained toward now, and the progression decisions
# that target has produced.
#
# The decisions are the point. Elsewhere in the app a progression decision is
# only visible for a moment, on the session that produced it; here the whole
# chain for a lift is readable in one place, retractions included, so a user can
# see why a load moved when it did.
class ExerciseHistory
  DEFAULT_SESSION_LIMIT = 12
  DECISION_LIMIT = 10

  # One workout's worth of this lift, with the working-set summary the page
  # renders. `sets` keeps warm-ups so the log stays faithful; the summary
  # numbers deliberately do not.
  Appearance = Data.define(:workout_session, :sets, :working_sets, :top_set, :volume_kg) do
    def performed_at = workout_session.performed_at
    def any_working_sets? = working_sets.any?
  end

  def initialize(user, exercise, session_limit: DEFAULT_SESSION_LIMIT)
    @user = user
    @exercise = exercise
    @session_limit = session_limit
  end

  def appearances
    @appearances ||= sets_by_session.map { |workout_session, sets| build_appearance(workout_session, sets) }
  end

  def active_prescription
    return @active_prescription if defined?(@active_prescription)

    @active_prescription = user.exercise_prescriptions
      .active
      .find_by(exercise: exercise)
  end

  # Retired targets, newest first — the effective-dated trail behind the current one.
  def past_prescriptions
    @past_prescriptions ||= user.exercise_prescriptions
      .where(exercise: exercise)
      .where.not(ended_on: nil)
      .order(started_on: :desc)
      .to_a
  end

  # Progression decisions for this lift, including retracted ones: a withdrawn
  # recommendation is part of the audit trail, not something to hide.
  def progression_decisions
    @progression_decisions ||= user.coaching_decisions
      .of_type("double_progression")
      .for_input("exercise_id", exercise.id)
      .latest_first
      .limit(DECISION_LIMIT)
      .to_a
  end

  def last_performed_on
    appearances.first&.performed_at&.to_date
  end

  def total_working_sets
    @total_working_sets ||= working_set_scope.count
  end

  def session_count
    @session_count ||= working_set_scope.distinct.count(:workout_session_id)
  end

  def heaviest_set
    @heaviest_set ||= working_set_scope.where.not(weight_kg: nil).order(weight_kg: :desc, reps: :desc).first
  end

  def ever_logged?
    appearances.any?
  end

  private

  attr_reader :user, :exercise, :session_limit

  def working_set_scope
    SetEntry
      .joins(:workout_session)
      .where(workout_sessions: { user_id: user.id })
      .where(exercise_id: exercise.id, is_warmup: false)
  end

  # The most recent sessions containing this lift, newest first, with their sets.
  def sets_by_session
    sessions = user.workout_sessions
      .where(id: SetEntry.where(exercise_id: exercise.id).select(:workout_session_id))
      .order(performed_at: :desc)
      .limit(session_limit)
      .to_a
    return [] if sessions.empty?

    grouped = SetEntry
      .where(workout_session_id: sessions.map(&:id), exercise_id: exercise.id)
      .order(:set_index)
      .group_by(&:workout_session_id)

    sessions.filter_map do |session|
      sets = grouped[session.id]
      [ session, sets ] if sets.present?
    end
  end

  def build_appearance(workout_session, sets)
    working_sets = sets.reject(&:is_warmup?)
    Appearance.new(
      workout_session: workout_session,
      sets: sets,
      working_sets: working_sets,
      top_set: working_sets.select { |set| set.weight_kg.present? }.max_by { |set| [ set.weight_kg, set.reps.to_i ] },
      volume_kg: working_sets.sum { |set| set.weight_kg.to_f * set.reps.to_i }.round
    )
  end
end
