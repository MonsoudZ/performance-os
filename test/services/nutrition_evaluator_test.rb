require "test_helper"

class NutritionEvaluatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.goal_periods.create!(
      goal_type: "build_muscle",
      params: { "target_kcal" => 2_800, "target_protein_g" => 180 },
      started_on: Date.current
    )
  end

  test "reports a protein gap from snapshotted food totals" do
    @user.food_log_entries.create!(
      logged_at: Time.current,
      quantity_grams: 500,
      kcal: 2_600,
      protein_g: 120,
      carb_g: 330,
      fat_g: 80
    )

    decision = NutritionEvaluator.new(@user).call

    assert_equal "protein_low", decision.output["status"]
    assert_equal 60, decision.output.dig("remaining", "protein_g")
    assert_equal "goal_params", decision.output.dig("targets", "source")
  end

  test "is idempotent for unchanged evidence" do
    first = NutritionEvaluator.new(@user).call

    assert_no_difference "CoachingDecision.count" do
      assert_equal first, NutritionEvaluator.new(@user).call
    end
  end
end
