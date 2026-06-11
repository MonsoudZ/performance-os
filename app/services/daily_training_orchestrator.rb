class DailyTrainingOrchestrator
  RULE_KEY = "daily_training_orchestrator.v1"
  RULE_VERSION = "1.0.0"

  def initialize(user, plan_date: nil)
    @user = user
    @plan_date = plan_date || user.local_date
  end

  def call
    return unless readiness_decision
    return current_parent if current_parent_matches?

    ApplicationRecord.transaction do
      parent = CoachingDecision.create!(
        user: user,
        decision_type: "daily_training",
        rule_key: RULE_KEY,
        rule_version: RULE_VERSION,
        inputs: serialized_input_snapshot,
        output: composed_output,
        citations: [],
        confidence: aggregate_confidence
      )

      parent.child_links.create!(child_decision: readiness_decision, role: "readiness")
      progression_decisions.each_value do |decision|
        parent.child_links.create!(child_decision: decision, role: "progression")
      end
      parent.child_links.create!(child_decision: nutrition_decision, role: "nutrition") if nutrition_decision

      parent
    end
  end

  private

  attr_reader :user, :plan_date

  def readiness_decision
    @readiness_decision ||= user.coaching_decisions
      .where(decision_type: "daily_readiness", rule_key: ReadinessEvaluator::RULE_KEY)
      .where("inputs ->> 'metric_date' = ?", plan_date.iso8601)
      .order(created_at: :desc)
      .first
  end

  def active_goal
    @active_goal ||= user.goal_periods
      .where("started_on <= ? AND (ended_on IS NULL OR ended_on >= ?)", plan_date, plan_date)
      .order(started_on: :desc)
      .first
  end

  def prescriptions
    @prescriptions ||= user.exercise_prescriptions
      .active_on(plan_date)
      .includes(:exercise)
      .order("exercises.name")
      .to_a
  end

  def progression_decisions
    @progression_decisions ||= prescriptions.each_with_object({}) do |prescription, decisions|
      decision = user.coaching_decisions
        .where(decision_type: "double_progression")
        .where("inputs ->> 'exercise_id' = ?", prescription.exercise_id.to_s)
        .where("created_at <= ?", plan_date.end_of_day)
        .order(created_at: :desc)
        .first
      decisions[prescription.exercise_id] = decision if decision
    end
  end

  def nutrition_decision
    @nutrition_decision ||= user.coaching_decisions
      .where(decision_type: "daily_nutrition", rule_key: NutritionEvaluator::RULE_KEY)
      .where("inputs ->> 'nutrition_date' = ?", plan_date.iso8601)
      .order(created_at: :desc)
      .first
  end

  def input_snapshot
    {
      "plan_date" => plan_date,
      "active_goal" => active_goal_snapshot,
      "readiness_decision_id" => readiness_decision.id,
      "progression_decision_ids" => progression_decisions.values.map(&:id),
      "nutrition_decision_id" => nutrition_decision&.id,
      "prescription_ids" => prescriptions.map(&:id),
      "conditioning" => conditioning_identity,
      "mesocycle" => mesocycle_identity
    }
  end

  def mesocycle_identity
    return unless active_mesocycle

    {
      "id" => active_mesocycle.id,
      "phase" => active_mesocycle.phase(plan_date),
      "week" => active_mesocycle.current_week(plan_date)
    }
  end

  # Compact conditioning state so the plan regenerates when the week's
  # conditioning changes.
  def conditioning_identity
    {
      "sessions" => conditioning_summary.session_count,
      "distance_km" => conditioning_summary.total_distance_km,
      "zone2_minutes" => conditioning_summary.zone2_minutes
    }
  end

  def current_parent
    @current_parent ||= user.coaching_decisions
      .where(decision_type: "daily_training", rule_key: RULE_KEY)
      .where("inputs ->> 'plan_date' = ?", plan_date.iso8601)
      .order(created_at: :desc)
      .first
  end

  def current_parent_matches?
    return false unless current_parent

    comparable_keys = %w[
      active_goal
      readiness_decision_id
      progression_decision_ids
      nutrition_decision_id
      prescription_ids
      conditioning
      mesocycle
    ]

    current_parent.inputs.slice(*comparable_keys) == serialized_input_snapshot.slice(*comparable_keys)
  end

  def serialized_input_snapshot
    @serialized_input_snapshot ||= JSON.parse(input_snapshot.to_json)
  end

  def composed_output
    {
      "status" => readiness_status,
      "headline" => headline_for(execution_mode),
      "guidance" => guidance_for(execution_mode),
      "readiness_score" => readiness_decision.output["readiness_score"],
      "goal" => active_goal&.goal_type,
      "session_directive" => readiness_decision.output["guidance"],
      "nutrition" => nutrition_output,
      "conditioning" => conditioning_output,
      "mesocycle" => mesocycle_output,
      "lifts" => prescriptions.map { |prescription| lift_directive(prescription, execution_mode) }
    }
  end

  def readiness_status
    @readiness_status ||= readiness_decision.output.fetch("status")
  end

  def active_mesocycle
    return @active_mesocycle if defined?(@active_mesocycle)

    @active_mesocycle = user.mesocycles.active_on(plan_date).order(started_on: :desc).first
  end

  def deload_week?
    active_mesocycle&.deload?(plan_date) || false
  end

  # A planned deload overrides readiness; otherwise the day runs on readiness.
  def execution_mode
    @execution_mode ||= deload_week? ? "deload" : readiness_status
  end

  def mesocycle_output
    return unless active_mesocycle

    {
      "name" => active_mesocycle.label,
      "week" => active_mesocycle.current_week(plan_date),
      "total_weeks" => active_mesocycle.weeks,
      "phase" => active_mesocycle.phase(plan_date),
      "deload" => deload_week?
    }
  end

  def conditioning_summary
    @conditioning_summary ||= WeeklyConditioningSummary.new(user, week_start: plan_date.beginning_of_week).call
  end

  def conditioning_output
    @conditioning_output ||= ConditioningDirective.new(
      goal: active_goal,
      readiness_status: readiness_status,
      summary: conditioning_summary
    ).call
  end

  def headline_for(execution_mode)
    case execution_mode
    when "deload" then "Deload week — back off to recover"
    when "recover" then "Make recovery the training goal"
    when "steady" then "Train the plan, trim the ambition"
    when "push"
      progression_decisions.values.any? { |decision| decision.output["status"] == "increase" } ?
        "Use the progress you’ve earned" :
        "Run the plan as written"
    end
  end

  def guidance_for(execution_mode)
    goal_context = active_goal ? "Your current goal is #{active_goal.goal_type.humanize.downcase}." : "No active goal is set."

    training_guidance = case execution_mode
    when "deload"
      "#{goal_context} This is a planned deload — roughly halve working sets, keep loads comfortable, and let accumulated fatigue clear before the next block."
    when "recover"
      "#{goal_context} Keep the movement pattern, reduce prescribed working sets by 30–40%, and do not treat today as a progression test."
    when "steady"
      "#{goal_context} Keep prescribed loads, cap effort around RPE 8, and stop at the planned volume."
    when "push"
      "#{goal_context} Follow each lift’s progression directive and use warm-ups as the final readiness check."
    end

    nutrition_decision ? "#{training_guidance} Nutrition: #{nutrition_decision.output["headline"].downcase}." : training_guidance
  end

  def nutrition_output
    return {
      "status" => "missing",
      "headline" => "Nutrition evidence unavailable",
      "guidance" => "Log food or body weight to add nutrition support to today’s plan."
    } unless nutrition_decision

    nutrition_decision.output.merge("decision_id" => nutrition_decision.id)
  end

  def lift_directive(prescription, execution_mode)
    progression = progression_decisions[prescription.exercise_id]
    sets = working_sets_for(prescription)
    base = {
      "exercise_id" => prescription.exercise_id,
      "exercise_name" => prescription.exercise.name,
      "prescription_id" => prescription.id,
      "target" => prescription.target_label,
      "working_sets" => sets,
      "progression_decision_id" => progression&.id
    }

    return base.merge(deload_lift_output(sets)) if execution_mode == "deload"
    return base.merge(recovery_lift_output(progression, sets)) if execution_mode == "recover"
    return base.merge(steady_lift_output(progression, sets)) if execution_mode == "steady"

    base.merge(push_lift_output(progression, sets))
  end

  # Effective working sets for the day: the deload/recover reductions, or the
  # prescription baseline plus the accumulation ramp.
  def working_sets_for(prescription)
    base = prescription.working_sets
    case execution_mode
    when "deload" then [ (base * 0.5).ceil, 1 ].max
    when "recover" then [ (base * 0.6).ceil, 1 ].max
    else base + accumulation_bonus
    end
  end

  def accumulation_bonus
    @accumulation_bonus ||= active_mesocycle ? active_mesocycle.accumulation_set_bonus(plan_date) : 0
  end

  def volume_note(sets)
    return "" unless accumulation_bonus.positive?

    " Volume ramp: aim for #{sets} working #{'set'.pluralize(sets)} this week."
  end

  def deload_lift_output(sets)
    {
      "action" => "deload",
      "headline" => "#{sets} easy working #{'set'.pluralize(sets)}",
      "guidance" => "Planned deload — cut volume, keep the load comfortable, and leave several reps in reserve. No progression test this week."
    }
  end

  def recovery_lift_output(progression, sets)
    {
      "action" => "reduce",
      "headline" => "#{sets} easy working #{'set'.pluralize(sets)}",
      "guidance" => progression_context(progression, "Keep the current load and leave at least 3 reps in reserve.")
    }
  end

  def steady_lift_output(progression, sets)
    if progression&.output&.fetch("status", nil) == "increase"
      {
        "action" => "conditional_increase",
        "headline" => "#{format_weight(progression.output["next_weight_kg"])} kg if warm-ups are crisp",
        "guidance" => "The load increase is earned, but keep effort capped near RPE 8 today.#{volume_note(sets)}"
      }
    else
      {
        "action" => "hold",
        "headline" => progression&.output&.fetch("headline", nil) || "Follow the current prescription",
        "guidance" => progression_context(progression, "Stay inside the prescribed rep and RIR range.#{volume_note(sets)}")
      }
    end
  end

  def push_lift_output(progression, sets)
    if progression&.output&.fetch("status", nil) == "increase"
      {
        "action" => "increase",
        "headline" => "#{format_weight(progression.output["next_weight_kg"])} kg",
        "guidance" => "#{progression.output["guidance"]}#{volume_note(sets)}"
      }
    elsif progression
      {
        "action" => progression.output["status"],
        "headline" => progression.output["headline"],
        "guidance" => "#{progression.output["guidance"]}#{volume_note(sets)}"
      }
    else
      {
        "action" => "establish",
        "headline" => "Establish today’s baseline",
        "guidance" => "Follow the active prescription; no prior progression decision exists yet.#{volume_note(sets)}"
      }
    end
  end

  def progression_context(progression, fallback)
    progression ? "#{progression.output["headline"]}. #{fallback}" : fallback
  end

  def active_goal_snapshot
    return unless active_goal

    active_goal.attributes.slice("id", "goal_type", "params", "started_on")
  end

  def aggregate_confidence
    confidences = [ readiness_decision.confidence ] +
      progression_decisions.values.map(&:confidence) +
      [ nutrition_decision&.confidence ].compact
    return "low" if confidences.include?("low")
    return "moderate" if confidences.include?("moderate")

    "high"
  end

  def format_weight(value)
    format("%.2f", value).sub(/\.?0+$/, "")
  end
end
