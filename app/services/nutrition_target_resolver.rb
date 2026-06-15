class NutritionTargetResolver
  PROTEIN_G_PER_KG = {
    "build_muscle" => 1.8,
    "lose_fat" => 2.0,
    "increase_strength" => 1.6,
    "athletic_performance" => 1.6,
    "vertical_jump" => 1.6,
    "marathon" => 1.4,
    "longevity" => 1.4
  }.freeze

  CALORIE_ADJUSTMENTS = {
    "build_muscle" => 250,
    "lose_fat" => -500
  }.freeze

  def initialize(user, goal:, target_date:)
    @user = user
    @goal = goal
    @target_date = target_date
  end

  def call
    {
      "kcal" => calorie_target,
      "protein_g" => protein_target,
      "source" => target_source,
      "weight_kg" => trend_weight&.to_f,
      "adjustment_decision_id" => nutrition_adjustment&.id,
      "calorie_delta" => nutrition_adjustment&.output&.fetch("calorie_delta", nil)
    }
  end

  private

  attr_reader :user, :goal, :target_date

  def calorie_target
    adjusted_target = nutrition_adjustment&.output&.fetch("target_kcal", nil)
    return adjusted_target.to_f if adjusted_target

    base_calorie_target
  end

  def base_calorie_target
    explicit = goal&.params&.fetch("target_kcal", nil)
    return explicit.to_f if explicit
    return unless expenditure

    expenditure.estimated_tdee.to_f + CALORIE_ADJUSTMENTS.fetch(goal&.goal_type, 0)
  end

  def protein_target
    explicit = goal&.params&.fetch("target_protein_g", nil)
    return explicit.to_f if explicit
    return unless trend_weight

    multiplier = PROTEIN_G_PER_KG.fetch(goal&.goal_type, 1.6)
    (trend_weight * multiplier).round
  end

  def expenditure
    @expenditure ||= user.expenditure_estimates
      .where("estimate_date <= ?", target_date)
      .order(estimate_date: :desc)
      .first
  end

  def trend_weight
    @trend_weight ||= user.weight_trends
      .where("trend_date <= ?", target_date)
      .order(trend_date: :desc)
      .pick(:ewma_kg)
  end

  def nutrition_adjustment
    return @nutrition_adjustment if defined?(@nutrition_adjustment)

    @nutrition_adjustment = user.coaching_decisions
      .active_evidence
      .of_type("nutrition_adjustment")
      .where(rule_key: NutritionAdjustmentEvaluator::RULE_KEY)
      .where("(output ->> 'effective_on')::date <= ?", target_date)
      .order(Arel.sql("(output ->> 'effective_on')::date DESC"), created_at: :desc)
      .first
  end

  def target_source
    return "weekly_adjustment" if nutrition_adjustment
    return "goal_params" if goal&.params&.key?("target_kcal") || goal&.params&.key?("target_protein_g")
    return "adaptive_expenditure" if expenditure

    "body_weight_default"
  end
end
