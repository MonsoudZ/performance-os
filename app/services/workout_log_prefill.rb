class WorkoutLogPrefill
  Context = Data.define(:entry, :prescription, :last_set)

  def initialize(user, workout_session:, log_date:)
    @user = user
    @workout_session = workout_session
    @log_date = log_date
  end

  def call
    return contexts_for_existing_entries if workout_session.set_entries.any?

    prescriptions.flat_map do |prescription|
      last_sets = last_working_sets_for(prescription.exercise)
      target_weight = target_weight_for(prescription, last_sets)

      prescription.working_sets.times.map do |index|
        entry = workout_session.set_entries.build(
          exercise: prescription.exercise,
          set_index: index + 1,
          weight_kg: target_weight,
          reps: prescription.rep_max,
          rir: prescription.target_rir_min
        )
        Context.new(entry:, prescription:, last_set: last_sets[index])
      end
    end
  end

  private

  attr_reader :user, :workout_session, :log_date

  def prescriptions
    @prescriptions ||= user.exercise_prescriptions
      .active_on(log_date)
      .includes(:exercise)
      .order("exercises.name")
  end

  def contexts_for_existing_entries
    workout_session.set_entries.map do |entry|
      prescription = prescriptions.find { |candidate| candidate.exercise_id == entry.exercise_id }
      last_set = last_working_sets_for(entry.exercise)[entry.set_index.to_i - 1]
      Context.new(entry:, prescription:, last_set:)
    end
  end

  def last_working_sets_for(exercise)
    return [] unless exercise

    user.workout_sessions
      .where("performed_at < ?", workout_session.performed_at || Time.current)
      .joins(:set_entries)
      .where(set_entries: { exercise_id: exercise.id, is_warmup: false })
      .order(performed_at: :desc)
      .first
      &.set_entries
      &.select { |entry| entry.exercise_id == exercise.id && !entry.is_warmup? }
      &.sort_by(&:set_index) || []
  end

  def target_weight_for(prescription, last_sets)
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
