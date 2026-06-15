class NutritionEvaluator
  RULE_KEY = "daily_nutrition.v1"
  RULE_VERSION = "1.0.0"

  def initialize(user, nutrition_date: nil)
    @user = user
    @nutrition_date = nutrition_date || user.local_date
  end

  def call
    return current_decision if current_decision_matches?

    user.coaching_decisions.create!(
      decision_type: "daily_nutrition",
      rule_key: RULE_KEY,
      rule_version: RULE_VERSION,
      inputs: serialized_inputs,
      output: output,
      citations: [],
      confidence: confidence
    )
  end

  private

  attr_reader :user, :nutrition_date

  def entries
    @entries ||= user.food_log_entries
      .where(logged_at: user.local_day_range(nutrition_date))
      .order(:logged_at)
      .to_a
  end

  def totals
    @totals ||= {
      "kcal" => entries.sum(&:kcal).to_f.round(1),
      "protein_g" => entries.sum(&:protein_g).to_f.round(1),
      "carb_g" => entries.sum(&:carb_g).to_f.round(1),
      "fat_g" => entries.sum(&:fat_g).to_f.round(1)
    }
  end

  def active_goal
    @active_goal ||= user.goal_periods
      .where("started_on <= ? AND (ended_on IS NULL OR ended_on >= ?)", nutrition_date, nutrition_date)
      .order(started_on: :desc)
      .first
  end

  def targets
    @targets ||= NutritionTargetResolver.new(user, goal: active_goal, target_date: nutrition_date).call
  end

  def input_snapshot
    {
      "nutrition_date" => nutrition_date,
      "food_log_entry_ids" => entries.map(&:id),
      "goal_period_id" => active_goal&.id,
      "weight_trend_date" => latest_weight_trend&.trend_date,
      "expenditure_estimate_date" => latest_expenditure&.estimate_date,
      "targets" => targets
    }
  end

  def serialized_inputs
    @serialized_inputs ||= JSON.parse(input_snapshot.to_json)
  end

  def current_decision
    @current_decision ||= user.coaching_decisions
      .active_evidence
      .of_type("daily_nutrition")
      .where(rule_key: RULE_KEY)
      .for_input("nutrition_date", nutrition_date.iso8601)
      .latest_first
      .first
  end

  def current_decision_matches?
    current_decision&.inputs == serialized_inputs
  end

  def output
    {
      "status" => status,
      "headline" => headline,
      "guidance" => guidance,
      "totals" => totals,
      "targets" => targets,
      "remaining" => remaining
    }
  end

  def status
    return "unlogged" if entries.empty?
    return "protein_low" if protein_ratio && protein_ratio < 0.9
    return "under_fueled" if calorie_ratio && calorie_ratio < 0.9
    return "over_target" if calorie_ratio && calorie_ratio > 1.1

    "on_track"
  end

  def headline
    case status
    when "unlogged" then "Log nutrition to complete the plan"
    when "protein_low" then "Close the protein gap"
    when "under_fueled" then "Fuel the work"
    when "over_target" then "Calories are above today’s target"
    when "on_track" then "Nutrition is on track"
    end
  end

  def guidance
    case status
    when "unlogged"
      "No food is logged today, so the engine cannot verify energy or protein support."
    when "protein_low"
      "#{remaining["protein_g"].ceil} g protein remains. Prioritize a protein-dense meal before adding discretionary calories."
    when "under_fueled"
      "#{remaining["kcal"].ceil} kcal remains. Add energy around training while keeping protein on target."
    when "over_target"
      "You are #{remaining["kcal"].abs.ceil} kcal above target. Keep the next meal protein-forward and lower in energy density."
    when "on_track"
      "Energy and protein are within the daily target bands."
    end
  end

  def remaining
    {
      "kcal" => targets["kcal"] ? (targets["kcal"] - totals["kcal"]).round(1) : nil,
      "protein_g" => targets["protein_g"] ? (targets["protein_g"] - totals["protein_g"]).round(1) : nil
    }
  end

  def protein_ratio
    totals["protein_g"] / targets["protein_g"] if targets["protein_g"].to_f.positive?
  end

  def calorie_ratio
    totals["kcal"] / targets["kcal"] if targets["kcal"].to_f.positive?
  end

  def latest_weight_trend
    @latest_weight_trend ||= user.weight_trends
      .where("trend_date <= ?", nutrition_date)
      .order(trend_date: :desc)
      .first
  end

  def latest_expenditure
    @latest_expenditure ||= user.expenditure_estimates
      .where("estimate_date <= ?", nutrition_date)
      .order(estimate_date: :desc)
      .first
  end

  def confidence
    return "low" if entries.empty? || targets["protein_g"].nil?
    return "high" if targets["kcal"] && targets["source"] == "goal_params"
    return latest_expenditure.confidence if latest_expenditure

    "moderate"
  end
end
