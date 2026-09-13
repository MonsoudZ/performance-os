class DoubleProgressionEvaluator
  RULE_KEY = "double_progression.v1"
  # 3.0.0: `inputs` gains "prior_decision_ids" — the earlier decisions the stall
  # rule reads to turn a third hold at the same load into a deload. They were
  # always part of what the rule saw and never part of what it recorded, which
  # left the snapshot unable to answer why a deload was called, and left this
  # evaluator unable to tell whether a re-run would reach the same conclusion.
  #
  # 2.0.0: the rep range, effort target and set count are composed by
  # TrainingTargets rather than read off the prescription, because a training
  # block now owns its scheme instead of having it applied to every target. The
  # snapshot gains a "targets" key recording what was actually in force and where
  # it came from, which the prescription alone no longer answers.
  RULE_VERSION = "3.0.0"
  STALL_SESSION_COUNT = 3
  DELOAD_PERCENT = 0.10

  def initialize(workout_session)
    @workout_session = workout_session
  end

  def call
    grouped_working_sets.filter_map do |exercise, sets|
      prescription = prescription_for(exercise)
      next unless prescription

      decision_for(exercise, prescription, sets)
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

  # The block in force when the session was performed, not today — a decision is
  # a record of what was prescribed at the time.
  def training_targets
    @training_targets ||= TrainingTargets.new(workout_session.user, on: session_date)
  end

  def session_date
    @session_date ||= workout_session.user.local_date_at(workout_session.performed_at)
  end

  def prescription_for(exercise)
    workout_session.user.exercise_prescriptions
      .where(exercise: exercise)
      .active_on(session_date)
      .order(started_on: :desc)
      .first
  end

  # Idempotent, like every other evaluator: the recompute pipeline re-runs these
  # freely — a retried job, a second save — and a rule that wrote a new decision
  # each time would leave a lift's history full of identical entries that only
  # differ by timestamp.
  def decision_for(exercise, prescription, sets)
    targets = training_targets.targets_for(prescription)
    evaluated_sets = sets.sort_by(&:set_index).first(targets.working_sets)
    priors = prior_decisions(exercise, prescription)
    inputs = serialized_inputs(exercise, prescription, targets, evaluated_sets, priors)

    current = current_decisions[exercise.id]
    return current if current&.inputs == inputs

    CoachingDecision.create!(
      user: workout_session.user,
      decision_type: "double_progression",
      rule_key: RULE_KEY,
      rule_version: RULE_VERSION,
      inputs: inputs,
      output: outcome_for(exercise, prescription, targets, evaluated_sets, priors),
      citations: [],
      confidence: confidence_for(targets, evaluated_sets)
    )
  end

  # Round-tripped through JSON so the comparison above is against the same shapes
  # Postgres hands back: a BigDecimal column and a Date read back as a string and
  # a float, and an unparsed snapshot would never match.
  def serialized_inputs(exercise, prescription, targets, sets, priors)
    JSON.parse({
      "workout_session_id" => workout_session.id,
      "exercise_id" => exercise.id,
      "exercise_name" => exercise.name,
      "prescription" => prescription_snapshot(prescription),
      "targets" => targets_snapshot(targets),
      "sets" => set_snapshots(sets),
      "prior_decision_ids" => priors.map(&:id)
    }.to_json)
  end

  # The live decisions this session has already produced, one per exercise,
  # newest first. Loaded once rather than per lift.
  #
  # Scoped to this rule version: a decision written by an older version answered
  # a different question, so it is never a match for this one even if its inputs
  # happen to look the same.
  def current_decisions
    @current_decisions ||= workout_session.user.coaching_decisions
      .active_evidence
      .of_type("double_progression")
      .where(rule_key: RULE_KEY, rule_version: RULE_VERSION)
      .for_input("workout_session_id", workout_session.id)
      .latest_first
      .each_with_object({}) { |decision, memo| memo[decision.inputs["exercise_id"]] ||= decision }
  end

  def outcome_for(exercise, prescription, targets, sets, priors)
    return insufficient_outcome(targets, sets) if sets.size < targets.working_sets

    current_weight = progression_load(prescription, sets)

    if qualifies_for_increase?(prescription, targets, sets)
      next_weight = current_weight + prescription.increment_kg
      {
        "status" => "increase",
        "headline" => "Add #{format_weight(prescription.increment_kg)} kg next time",
        "guidance" => increase_guidance(prescription),
        "current_weight_kg" => current_weight.to_f,
        "next_weight_kg" => next_weight.to_f
      }
    else
      hold = {
        "status" => "hold",
        "headline" => "Keep the load",
        "guidance" => hold_reason(prescription, targets, sets),
        "current_weight_kg" => current_weight.to_f,
        "next_weight_kg" => current_weight.to_f
      }
      stalled?(priors, hold["current_weight_kg"]) ?
        deload_outcome(prescription, hold["current_weight_kg"]) :
        hold
    end
  end

  # Sets that gate the increase: every working set for straight-set double
  # progression, only the heaviest (top) set for top-set progression.
  def decisive_sets(prescription, sets)
    prescription.top_set? ? [ top_set(sets) ] : sets
  end

  def top_set(sets)
    sets.max_by { |set| set.weight_kg.to_f }
  end

  def progression_load(prescription, sets)
    decisive_sets(prescription, sets).map(&:weight_kg).max
  end

  def qualifies_for_increase?(prescription, targets, sets)
    decisive = decisive_sets(prescription, sets)
    top_range_hit = decisive.all? { |set| set.reps >= targets.rep_max }
    rir_on_target = decisive.all? do |set|
      set.rir.between?(targets.target_rir_min, targets.target_rir_max)
    end
    # Straight sets must also be run at one consistent load; top-set ramps are
    # judged on the top set alone, so a ramp up to it is fine.
    load_qualifies = prescription.top_set? || consistent_load?(sets)

    top_range_hit && rir_on_target && load_qualifies
  end

  def increase_guidance(prescription)
    if prescription.top_set?
      "The top set reached the top of the rep range at the target RIR."
    else
      "Every prescribed set reached the top of the rep range at the target RIR."
    end
  end

  def insufficient_outcome(targets, sets)
    {
      "status" => "insufficient",
      "headline" => "No progression call yet",
      "guidance" => "Logged #{sets.size} of #{targets.working_sets} prescribed working sets."
    }
  end

  def hold_reason(prescription, targets, sets)
    decisive = decisive_sets(prescription, sets)
    if decisive.any? { |set| set.reps < targets.rep_min }
      "At least one set fell below the target rep range. Repeat the load and rebuild reps."
    elsif decisive.any? { |set| set.reps < targets.rep_max }
      prescription.top_set? ?
        "The top set has not reached the top of the rep range yet." :
        "The top of the rep range is not complete across every working set yet."
    elsif decisive.any? { |set| set.rir < targets.target_rir_min }
      "The reps were achieved with less reserve than prescribed. Repeat the load before increasing."
    elsif decisive.any? { |set| set.rir > targets.target_rir_max }
      prescription.top_set? ?
        "The top set left more in reserve than the target RIR. Keep the load until the effort lands in range." :
        "The load was easier than the target RIR, but the set pattern was not consistent enough to progress."
    else
      "Use one consistent working weight before increasing the prescription."
    end
  end

  def consistent_load?(sets)
    sets.map(&:weight_kg).uniq.one?
  end

  # The most recent sessions this lift was judged on, one decision per session,
  # excluding this one — a re-run of this session must not count its own earlier
  # verdict as evidence against itself.
  def prior_decisions(exercise, prescription)
    workout_session.user.coaching_decisions
      .active_evidence
      .of_type("double_progression")
      .where(rule_key: RULE_KEY)
      .for_input("exercise_id", exercise.id)
      .for_prescription(prescription.id)
      .latest_first
      .to_a
      .reject { |decision| decision.inputs["workout_session_id"] == workout_session.id }
      .uniq { |decision| decision.inputs["workout_session_id"] }
      .first(STALL_SESSION_COUNT - 1)
  end

  def stalled?(priors, current_weight)
    priors.size == STALL_SESSION_COUNT - 1 &&
      priors.all? do |decision|
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

  def confidence_for(targets, sets)
    sets.size >= targets.working_sets ? "high" : "low"
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
      "started_on",
      "progression_model"
    ).merge("follows_block_scheme" => prescription.follows_block_scheme)
  end

  # What was actually in force, and whether the block or the target itself set
  # it. Without this the snapshot records a rep range the rule may not have used.
  def targets_snapshot(targets)
    targets.to_h.transform_values { |value| value.is_a?(BigDecimal) ? value.to_f : value }
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
