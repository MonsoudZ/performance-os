require "test_helper"

class NutritionTargetResolverTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "uses explicit goal calorie and protein targets" do
    goal = build_goal("build_muscle", params: { "target_kcal" => 2_800, "target_protein_g" => 180 })

    result = resolve(goal)

    assert_equal 2_800.0, result["kcal"]
    assert_equal 180.0, result["protein_g"]
    assert_equal "goal_params", result["source"]
  end

  test "derives protein from body weight and the goal multiplier" do
    goal = build_goal("lose_fat")
    trend(80)

    # lose_fat multiplier is 2.0 g/kg.
    assert_equal 160, resolve(goal)["protein_g"]
  end

  test "derives calories from adaptive expenditure plus the goal adjustment" do
    goal = build_goal("lose_fat")
    expenditure(2_600)

    result = resolve(goal)

    assert_equal 2_100.0, result["kcal"] # 2,600 - 500
    assert_equal "adaptive_expenditure", result["source"]
  end

  test "adds the surplus for a muscle-building goal" do
    goal = build_goal("build_muscle")
    expenditure(2_600)

    assert_equal 2_850.0, resolve(goal)["kcal"] # 2,600 + 250
  end

  test "falls back to a body-weight default with no goal or expenditure" do
    trend(70)

    result = resolve(nil)

    assert_nil result["kcal"]
    assert_equal 112, result["protein_g"] # 70 * 1.6 default multiplier
    assert_equal "body_weight_default", result["source"]
  end

  test "a weekly adjustment overrides the goal target and wins the source" do
    goal = build_goal("build_muscle", started_on: Date.current - 10.days, params: { "target_kcal" => 2_800 })
    @user.coaching_decisions.create!(
      decision_type: "nutrition_adjustment",
      rule_key: NutritionAdjustmentEvaluator::RULE_KEY,
      rule_version: "1.0.0",
      inputs: {},
      citations: [],
      confidence: "moderate",
      output: { "target_kcal" => 2_650, "calorie_delta" => -150, "effective_on" => Date.current.iso8601 }
    )

    result = resolve(goal)

    assert_equal 2_650.0, result["kcal"]
    assert_equal "weekly_adjustment", result["source"]
    assert_equal(-150, result["calorie_delta"])
  end

  # An adjustment outranking every other source is the point of it; outranking
  # them forever is the bug. Two weeks is one missed review.
  test "an adjustment stops applying once it has expired" do
    goal = build_goal("lose_fat", started_on: Date.current - 60.days)
    expenditure(2_600)
    adjustment(
      effective_on: Date.current - NutritionAdjustmentEvaluator::AUTHORITY_DAYS - 1.day,
      expires_on: Date.current - 1.day
    )

    result = resolve(goal)

    assert_equal 2_100.0, result["kcal"] # back to 2,600 - 500
    assert_equal "adaptive_expenditure", result["source"]
    assert_nil result["adjustment_decision_id"]
  end

  test "an adjustment still inside its window applies" do
    goal = build_goal("lose_fat", started_on: Date.current - 60.days)
    expenditure(2_600)
    adjustment(effective_on: Date.current - 1.day, expires_on: Date.current)

    result = resolve(goal)

    assert_equal 2_650.0, result["kcal"]
    assert_equal "weekly_adjustment", result["source"]
  end

  # Decisions written before rule_version 2.0.0 carry no expires_on, and the
  # evaluator's short-circuit means they are never rewritten — so the bound has
  # to be derived for them or they would outlive the rule that replaced them.
  test "an adjustment predating expires_on is bounded from effective_on" do
    goal = build_goal("lose_fat", started_on: Date.current - 60.days)
    expenditure(2_600)
    adjustment(effective_on: Date.current - NutritionAdjustmentEvaluator::AUTHORITY_DAYS - 1.day)

    assert_equal "adaptive_expenditure", resolve(goal)["source"]
  end

  test "an adjustment predating expires_on still applies inside the derived window" do
    goal = build_goal("lose_fat", started_on: Date.current - 60.days)
    expenditure(2_600)
    adjustment(effective_on: Date.current - NutritionAdjustmentEvaluator::AUTHORITY_DAYS + 1.day)

    assert_equal "weekly_adjustment", resolve(goal)["source"]
  end

  # The boundary itself, because an off-by-one here silently changes a user's
  # calories on a day nobody is looking.
  test "an adjustment applies on its last day and not the day after" do
    goal = build_goal("lose_fat", started_on: Date.current - 60.days)
    expenditure(2_600)
    decision = adjustment(effective_on: Date.current - 5.days, expires_on: Date.current)

    assert_equal "weekly_adjustment", resolve(goal)["source"]

    decision.update_column(:output, decision.output.merge("expires_on" => (Date.current - 1.day).iso8601))
    assert_equal "adaptive_expenditure", resolve(goal)["source"]
  end

  private

  def adjustment(effective_on:, expires_on: :none)
    output = { "target_kcal" => 2_650, "calorie_delta" => -150, "effective_on" => effective_on.to_date.iso8601 }
    output["expires_on"] = expires_on.to_date.iso8601 unless expires_on == :none

    @user.coaching_decisions.create!(
      decision_type: "nutrition_adjustment",
      rule_key: NutritionAdjustmentEvaluator::RULE_KEY,
      rule_version: "2.0.0",
      inputs: {},
      citations: [],
      confidence: "moderate",
      output: output
    )
  end

  def resolve(goal)
    NutritionTargetResolver.new(@user, goal: goal, target_date: Date.current).call
  end

  def build_goal(goal_type, started_on: Date.current, params: {})
    @user.goal_periods.create!(goal_type: goal_type, started_on: started_on, params: params)
  end

  def trend(weight)
    @user.weight_trends.create!(trend_date: Date.current, raw_kg: weight, ewma_kg: weight)
  end

  def expenditure(tdee)
    @user.expenditure_estimates.create!(
      estimate_date: Date.current,
      estimated_tdee: tdee,
      intake_kcal: tdee,
      trend_weight_kg: 80,
      confidence: "moderate",
      computed_at: Time.current
    )
  end
end
