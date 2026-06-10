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

  private

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
