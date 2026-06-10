class WorkoutLogPrefill
  Context = Data.define(:entry, :prescription, :last_set)
  Plan = Data.define(:exercise, :prescription, :working_sets)

  def initialize(user, workout_session:, log_date:, workout_template: nil)
    @user = user
    @workout_session = workout_session
    @log_date = log_date
    @workout_template = workout_template
  end

  def call
    return contexts_for_existing_entries if workout_session.set_entries.any?

    exercise_plans.flat_map do |plan|
      last_sets = last_working_sets_for(plan.exercise)
      target_weight = target_weight_for(plan.prescription, last_sets)

      plan.working_sets.times.map do |index|
        entry = workout_session.set_entries.build(
          exercise: plan.exercise,
          set_index: index + 1,
          weight_kg: target_weight,
          reps: plan.prescription&.rep_max,
          rir: plan.prescription&.target_rir_min
        )
        Context.new(entry:, prescription: plan.prescription, last_set: last_sets[index])
      end
    end
  end

  private

  attr_reader :user, :workout_session, :log_date, :workout_template

  def exercise_plans
    @exercise_plans ||= if workout_template
      workout_template.workout_template_exercises.includes(:exercise).map do |item|
        prescription = prescription_for(item.exercise)
        Plan.new(exercise: item.exercise, prescription:, working_sets: prescription&.working_sets || 1)
      end
    else
      prescriptions.map do |prescription|
        Plan.new(exercise: prescription.exercise, prescription:, working_sets: prescription.working_sets)
      end
    end
  end

  def prescriptions
    @prescriptions ||= user.exercise_prescriptions.active_on(log_date).includes(:exercise).order("exercises.name")
  end

  def prescription_for(exercise)
    prescriptions
      .select { |prescription| prescription.exercise_id == exercise.id }
      .max_by(&:started_on)
  end

  def contexts_for_existing_entries
    workout_session.set_entries.map do |entry|
      prescription = prescription_for(entry.exercise)
      last_set = last_working_sets_for(entry.exercise)[entry.set_index.to_i - 1]
      Context.new(entry:, prescription:, last_set:)
    end
  end

  def last_working_sets_for(exercise)
    return [] unless exercise

    last_working_sets_by_exercise[exercise.id] || []
  end

  # Batches the per-exercise "most recent prior working sets" lookup into two
  # queries total (instead of one per exercise) since prefill runs on the
  # workout-logging hot path. Result shape matches the old per-exercise query:
  # the non-warmup sets of the most recent earlier session that trained the
  # exercise, ordered by set_index.
  def last_working_sets_by_exercise
    @last_working_sets_by_exercise ||= build_last_working_sets_by_exercise
  end

  def build_last_working_sets_by_exercise
    exercise_ids = relevant_exercise_ids
    return {} if exercise_ids.empty?

    cutoff = workout_session.performed_at || Time.current

    # Most recent prior session per exercise that has a non-warmup set for it.
    latest_session_per_exercise = SetEntry
      .joins(:workout_session)
      .where(workout_sessions: { user_id: user.id })
      .where(exercise_id: exercise_ids, is_warmup: false)
      .where(workout_sessions: { performed_at: ...cutoff })
      .select("DISTINCT ON (set_entries.exercise_id) set_entries.exercise_id, set_entries.workout_session_id")
      .order("set_entries.exercise_id, workout_sessions.performed_at DESC")
      .map { |row| [ row.exercise_id, row.workout_session_id ] }

    return {} if latest_session_per_exercise.empty?

    session_ids = latest_session_per_exercise.map(&:last).uniq
    entries = SetEntry
      .where(workout_session_id: session_ids, exercise_id: exercise_ids, is_warmup: false)
      .to_a

    latest_session_per_exercise.each_with_object({}) do |(exercise_id, session_id), memo|
      memo[exercise_id] = entries
        .select { |entry| entry.exercise_id == exercise_id && entry.workout_session_id == session_id }
        .sort_by(&:set_index)
    end
  end

  def relevant_exercise_ids
    if workout_session.set_entries.any?
      workout_session.set_entries.map(&:exercise_id).uniq
    else
      exercise_plans.map { |plan| plan.exercise.id }.uniq
    end
  end

  def target_weight_for(prescription, last_sets)
    return last_sets.filter_map(&:weight_kg).max unless prescription

    latest_progression_weight(prescription) || last_sets.filter_map(&:weight_kg).max
  end

  def latest_progression_weight(prescription)
    decision = user.coaching_decisions
      .where(decision_type: "double_progression")
      .where("inputs ->> 'exercise_id' = ?", prescription.exercise_id.to_s)
      .where("inputs #>> '{prescription,id}' = ?", prescription.id.to_s)
      .where("created_at <= ?", workout_session.performed_at || Time.current)
      .order(created_at: :desc)
      .first

    decision&.output&.fetch("next_weight_kg", nil)
  end
end
