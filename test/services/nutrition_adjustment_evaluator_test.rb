require "test_helper"

class NutritionAdjustmentEvaluatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.goal_periods.create!(
      goal_type: "build_muscle",
      params: { "target_kcal" => 2_800, "target_protein_g" => 180 },
      started_on: Date.current - 30.days
    )
  end

  test "turns a weekly decrease signal into the next effective target" do
    review = create_review("decrease")

    adjustment = NutritionAdjustmentEvaluator.new(review).call

    assert_equal "decrease", adjustment.output["status"]
    assert_equal(-150, adjustment.output["calorie_delta"])
    assert_equal 2_650, adjustment.output["target_kcal"]
    assert_equal Date.tomorrow.iso8601, adjustment.output["effective_on"]
    assert_equal [ review.id ], adjustment.child_decisions.pluck(:id)
    assert_equal [ "weekly_review" ], adjustment.child_links.pluck(:role)

    today = NutritionTargetResolver.new(@user, goal: @user.active_goal, target_date: Date.current).call
    tomorrow = NutritionTargetResolver.new(@user, goal: @user.active_goal, target_date: Date.tomorrow).call

    assert_equal 2_800, today["kcal"]
    assert_equal "goal_params", today["source"]
    assert_equal 2_650, tomorrow["kcal"]
    assert_equal "weekly_adjustment", tomorrow["source"]
    assert_equal adjustment.id, tomorrow["adjustment_decision_id"]
  end

  test "is idempotent for the same weekly review" do
    review = create_review("hold")
    first = NutritionAdjustmentEvaluator.new(review).call

    assert_no_difference [ "CoachingDecision.count", "CoachingDecisionLink.count" ] do
      assert_equal first, NutritionAdjustmentEvaluator.new(review).call
    end
  end

  test "does not apply another correction before a new weekly window" do
    first_review = create_review("decrease", period_end: Date.current)
    NutritionAdjustmentEvaluator.new(first_review).call
    second_review = create_review("decrease", period_end: Date.current + 1.day)

    second_adjustment = NutritionAdjustmentEvaluator.new(second_review).call

    assert_equal "cadence_locked", second_adjustment.output["status"]
    assert_equal 0, second_adjustment.output["calorie_delta"]
    assert_equal 2_650, second_adjustment.output["target_kcal"]
  end

  private

  def create_review(direction, period_end: Date.current)
    @user.coaching_decisions.create!(
      decision_type: "weekly_review",
      rule_key: WeeklyEvidenceReview::RULE_KEY,
      rule_version: "1.0.0",
      inputs: {
        "period_start" => (period_end - 6.days).iso8601,
        "period_end" => period_end.iso8601
      },
      output: {
        "status" => direction == "hold" ? "continue" : "adjust_calories",
        "calorie_direction" => direction,
        "period" => {
          "start" => (period_end - 6.days).iso8601,
          "end" => period_end.iso8601
        }
      },
      citations: [],
      confidence: "moderate"
    )
  end
end
