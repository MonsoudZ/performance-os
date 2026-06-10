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
