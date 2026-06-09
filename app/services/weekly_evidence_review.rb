class WeeklyEvidenceReview
  RULE_KEY = "weekly_evidence_review.v1"
  RULE_VERSION = "1.0.0"
  REVIEW_DAYS = 7
  RATE_BANDS = {
    "build_muscle" => { "minimum" => 0.25, "maximum" => 0.5 },
    "lose_fat" => { "minimum" => -1.0, "maximum" => -0.5 }
  }.freeze

  def initialize(user, period_end: nil)
    @user = user
    @period_end = period_end || user.local_date.beginning_of_week - 1.day
  end

  def call
    return current_decision if current_decision_matches?

    ApplicationRecord.transaction do
      review = user.coaching_decisions.create!(
        decision_type: "weekly_review",
        rule_key: RULE_KEY,
        rule_version: RULE_VERSION,
        inputs: serialized_inputs,
        output: output,
        citations: [],
        confidence: confidence
      )

      linked_decisions.each do |role, decisions|
        decisions.each { |decision| review.child_links.create!(child_decision: decision, role: role) }
      end

      review
    end
  end

  private

  attr_reader :user, :period_end

  def period_start
    @period_start ||= period_end - (REVIEW_DAYS - 1).days
  end

  def active_goal
    @active_goal ||= user.goal_periods
      .where("started_on <= ? AND (ended_on IS NULL OR ended_on >= ?)", period_end, period_end)
      .order(started_on: :desc)
      .first
  end

  def readiness_decisions
    @readiness_decisions ||= decisions_during("daily_readiness", "metric_date")
  end

  def nutrition_decisions
    @nutrition_decisions ||= decisions_during("daily_nutrition", "nutrition_date")
      .group_by { |decision| decision.inputs["nutrition_date"] }
      .values
      .map { |decisions| decisions.max_by(&:created_at) }
      .sort_by { |decision| decision.inputs["nutrition_date"] }
  end

  def progression_decisions
    @progression_decisions ||= user.coaching_decisions
      .where(decision_type: "double_progression", created_at: period_start.beginning_of_day..period_end.end_of_day)
      .order(:created_at)
      .to_a
  end

  def decisions_during(decision_type, date_key)
    user.coaching_decisions
      .where(decision_type: decision_type)
      .where("(inputs ->> ?)::date BETWEEN ? AND ?", date_key, period_start, period_end)
      .order(Arel.sql("inputs ->> '#{date_key}'"), :created_at)
      .to_a
  end

  def weight_trends
    @weight_trends ||= user.weight_trends
      .where(trend_date: period_start..period_end)
      .order(:trend_date)
      .to_a
  end

  def latest_expenditure
    return @latest_expenditure if defined?(@latest_expenditure)

    @latest_expenditure = user.expenditure_estimates
      .where("estimate_date <= ?", period_end)
      .order(estimate_date: :desc)
      .first
  end

  def linked_decisions
    {
      "readiness" => readiness_decisions,
      "progression" => progression_decisions,
      "nutrition" => nutrition_decisions
    }
  end

  def input_snapshot
    {
      "period_start" => period_start,
      "period_end" => period_end,
      "goal_period_id" => active_goal&.id,
      "goal_type" => active_goal&.goal_type,
      "readiness_decision_ids" => readiness_decisions.map(&:id),
      "progression_decision_ids" => progression_decisions.map(&:id),
      "nutrition_decision_ids" => nutrition_decisions.map(&:id),
      "weight_trends" => weight_trends.map { |trend| [ trend.trend_date, trend.ewma_kg ] },
      "expenditure_estimate_date" => latest_expenditure&.estimate_date
    }
  end

  def serialized_inputs
    @serialized_inputs ||= JSON.parse(input_snapshot.to_json)
  end

  def current_decision
    @current_decision ||= user.coaching_decisions
      .where(decision_type: "weekly_review", rule_key: RULE_KEY)
      .where("inputs ->> 'period_end' = ?", period_end.iso8601)
      .order(created_at: :desc)
      .first
  end

  def current_decision_matches?
    current_decision&.inputs == serialized_inputs
  end

  def output
    {
      "status" => review_status,
      "headline" => headline,
      "guidance" => guidance,
      "period" => {
        "start" => period_start,
        "end" => period_end
      },
      "goal" => active_goal&.goal_type,
      "evidence" => evidence,
      "weight_rate_pct_per_week" => weight_rate_pct_per_week,
      "target_rate_band" => rate_band,
      "calorie_direction" => calorie_direction
    }
  end

  def evidence
    {
      "readiness_days" => readiness_decisions.size,
      "average_readiness" => average_readiness,
      "nutrition_days" => nutrition_decisions.count { |decision| decision.output["status"] != "unlogged" },
      "average_calorie_adherence" => average_nutrition_adherence("kcal"),
      "average_protein_adherence" => average_nutrition_adherence("protein_g"),
      "progression_decisions" => progression_decisions.size,
      "progression_statuses" => progression_decisions.map { |decision| decision.output["status"] }.tally,
      "weight_trend_days" => weight_trends.size,
      "weight_start_kg" => weight_trends.first&.ewma_kg&.to_f,
      "weight_end_kg" => weight_trends.last&.ewma_kg&.to_f,
      "adaptive_tdee" => latest_expenditure&.estimated_tdee&.to_f,
      "adaptive_tdee_confidence" => latest_expenditure&.confidence
    }
  end

  def sufficient_evidence?
    evidence["nutrition_days"] >= REVIEW_DAYS &&
      weight_trends.size >= REVIEW_DAYS &&
      weight_span_days >= REVIEW_DAYS - 1
  end

  def weight_span_days
    return 0 if weight_trends.size < 2

    (weight_trends.last.trend_date - weight_trends.first.trend_date).to_i
  end

  def weight_rate_pct_per_week
    return unless weight_span_days.positive?

    start_weight = weight_trends.first.ewma_kg.to_f
    change_pct = ((weight_trends.last.ewma_kg.to_f - start_weight) / start_weight) * 100
    (change_pct * 7 / weight_span_days).round(2)
  end

  def rate_band
    RATE_BANDS[active_goal&.goal_type]
  end

  def calorie_direction
    return "insufficient_evidence" unless sufficient_evidence?
    return "hold" unless rate_band && weight_rate_pct_per_week
    return "decrease" if weight_rate_pct_per_week > rate_band["maximum"]
    return "increase" if weight_rate_pct_per_week < rate_band["minimum"]

    "hold"
  end

  def review_status
    return "insufficient_evidence" unless sufficient_evidence?
    return "adjust_calories" if %w[increase decrease].include?(calorie_direction)

    "continue"
  end

  def headline
    case review_status
    when "insufficient_evidence" then "Keep collecting evidence"
    when "adjust_calories" then calorie_direction == "increase" ? "Increase the calorie target" : "Reduce the calorie target"
    else "The plan is working"
    end
  end

  def guidance
    return "A weekly correction requires 7 logged intake days and 7 daily weight trends spanning the week." unless sufficient_evidence?
    return "This goal does not use a body-weight rate band, so keep the current nutrition target and review training evidence." unless rate_band

    case calorie_direction
    when "increase"
      "The weight trend is below the #{rate_band_label} target. Add a small calorie step and observe another full week."
    when "decrease"
      "The weight trend is above the #{rate_band_label} target. Remove a small calorie step and observe another full week."
    else
      "The weight trend is inside the #{rate_band_label} target. Keep calories unchanged."
    end
  end

  def rate_band_label
    "#{rate_band["minimum"]}% to #{rate_band["maximum"]}% per week"
  end

  def average_readiness
    scores = readiness_decisions.filter_map { |decision| decision.output["readiness_score"]&.to_f }
    (scores.sum / scores.size).round(1) if scores.any?
  end

  def average_nutrition_adherence(nutrient)
    ratios = nutrition_decisions.filter_map do |decision|
      total = decision.output.dig("totals", nutrient)&.to_f
      target = decision.output.dig("targets", nutrient)&.to_f
      total / target if target&.positive?
    end
    (ratios.sum / ratios.size).round(2) if ratios.any?
  end

  def confidence
    return "low" unless sufficient_evidence?
    return "high" if readiness_decisions.size >= 5 && latest_expenditure&.confidence == "high"

    "moderate"
  end
end
