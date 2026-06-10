class DoubleProgressionEvaluator
  RULE_KEY = "double_progression.v1"
  RULE_VERSION = "1.0.0"
  STALL_SESSION_COUNT = 3
  DELOAD_PERCENT = 0.10

  def initialize(workout_session)
    @workout_session = workout_session
  end

  def call
    grouped_working_sets.filter_map do |exercise, sets|
      prescription = prescription_for(exercise)
      next unless prescription

      create_decision(exercise, prescription, sets)
    end
  end

  private

  attr_reader :workout_session

  def grouped_working_sets
    workout_session.set_entries
      .reject(&:is_warmup?)
      .select { |set| set.reps.present? && set.weight_kg.present? && set.rir.present? }
      .group_by(&:exercise)
  end

  def prescription_for(exercise)
    workout_session.user.exercise_prescriptions
      .where(exercise: exercise)
      .active_on(workout_session.user.local_date_at(workout_session.performed_at))
      .order(started_on: :desc)
      .first
  end

  def create_decision(exercise, prescription, sets)
    evaluated_sets = sets.sort_by(&:set_index).first(prescription.working_sets)
    outcome = outcome_for(exercise, prescription, evaluated_sets)

    CoachingDecision.create!(
      user: workout_session.user,
      decision_type: "double_progression",
      rule_key: RULE_KEY,
      rule_version: RULE_VERSION,
      inputs: {
        "workout_session_id" => workout_session.id,
        "exercise_id" => exercise.id,
        "exercise_name" => exercise.name,
        "prescription" => prescription_snapshot(prescription),
        "sets" => set_snapshots(evaluated_sets)
      },
      output: outcome,
      citations: [],
      confidence: confidence_for(prescription, evaluated_sets)
    )
  end

  def outcome_for(exercise, prescription, sets)
    return insufficient_outcome(prescription, sets) if sets.size < prescription.working_sets

    top_range_hit = sets.all? { |set| set.reps >= prescription.rep_max }
    rir_on_target = sets.all? do |set|
      set.rir.between?(prescription.target_rir_min, prescription.target_rir_max)
    end

    if top_range_hit && rir_on_target && consistent_load?(sets)
      current_weight = sets.map(&:weight_kg).max
      next_weight = current_weight + prescription.increment_kg
      {
        "status" => "increase",
        "headline" => "Add #{format_weight(prescription.increment_kg)} kg next time",
        "guidance" => "Every prescribed set reached the top of the rep range at the target RIR.",
        "current_weight_kg" => current_weight.to_f,
        "next_weight_kg" => next_weight.to_f
      }
    else
      hold = {
        "status" => "hold",
        "headline" => "Keep the load",
        "guidance" => hold_reason(prescription, sets),
        "current_weight_kg" => sets.map(&:weight_kg).max.to_f,
        "next_weight_kg" => sets.map(&:weight_kg).max.to_f
      }
      stalled?(exercise, prescription, hold["current_weight_kg"]) ?
        deload_outcome(prescription, hold["current_weight_kg"]) :
        hold
    end
  end

  def insufficient_outcome(prescription, sets)
    {
      "status" => "insufficient",
      "headline" => "No progression call yet",
      "guidance" => "Logged #{sets.size} of #{prescription.working_sets} prescribed working sets."
    }
  end

  def hold_reason(prescription, sets)
    if sets.any? { |set| set.reps < prescription.rep_min }
      "At least one set fell below the target rep range. Repeat the load and rebuild reps."
    elsif sets.any? { |set| set.reps < prescription.rep_max }
      "The top of the rep range is not complete across every working set yet."
    elsif sets.any? { |set| set.rir < prescription.target_rir_min }
      "The reps were achieved with less reserve than prescribed. Repeat the load before increasing."
    elsif sets.any? { |set| set.rir > prescription.target_rir_max }
      "The load was easier than the target RIR, but the set pattern was not consistent enough to progress."
    else
      "Use one consistent working weight before increasing the prescription."
    end
  end

  def consistent_load?(sets)
    sets.map(&:weight_kg).uniq.one?
  end

  def stalled?(exercise, prescription, current_weight)
    prior_decisions = workout_session.user.coaching_decisions
      .where(decision_type: "double_progression", rule_key: RULE_KEY)
      .where("inputs ->> 'exercise_id' = ?", exercise.id.to_s)
      .where("inputs #>> '{prescription,id}' = ?", prescription.id.to_s)
      .order(created_at: :desc)
      .to_a
      .uniq { |decision| decision.inputs["workout_session_id"] }
      .first(STALL_SESSION_COUNT - 1)

    prior_decisions.size == STALL_SESSION_COUNT - 1 &&
      prior_decisions.all? do |decision|
        decision.output["status"] == "hold" &&
          decision.output["current_weight_kg"].to_f.round(2) == current_weight.to_f.round(2)
      end
  end

  def deload_outcome(prescription, current_weight)
    deload_weight = rounded_deload_weight(current_weight, prescription.increment_kg.to_f)
    {
      "status" => "deload",
      "headline" => "Deload to #{format_weight(deload_weight)} kg",
      "guidance" => "Three consecutive sessions stalled at the same load. Reduce load by about 10%, rebuild the rep range, then resume progression.",
      "current_weight_kg" => current_weight.to_f,
      "next_weight_kg" => deload_weight,
      "stall_sessions" => STALL_SESSION_COUNT
    }
  end

  def rounded_deload_weight(current_weight, increment)
    raw_weight = current_weight.to_f * (1 - DELOAD_PERCENT)
    rounded = (raw_weight / increment).round * increment
    [ rounded, current_weight.to_f - increment ].min.round(2)
  end

  def confidence_for(prescription, sets)
    sets.size >= prescription.working_sets ? "high" : "low"
  end

  def prescription_snapshot(prescription)
    prescription.attributes.slice(
      "id",
      "rep_min",
      "rep_max",
      "target_rir_min",
      "target_rir_max",
      "increment_kg",
      "working_sets",
      "started_on"
    )
  end

  def set_snapshots(sets)
    sets.map do |set|
      set.attributes.slice("id", "set_index", "weight_kg", "reps", "rir")
    end
  end

  def format_weight(value)
    format("%.2f", value).sub(/\.?0+$/, "")
  end
end
