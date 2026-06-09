require "test_helper"

class WeeklyEvidenceReviewTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @period_end = Date.current
    @user.goal_periods.create!(
      goal_type: "build_muscle",
      params: { "target_kcal" => 2_800, "target_protein_g" => 180 },
      started_on: @period_end - 30.days
    )
  end

  test "recommends a correction when complete evidence exceeds the gain-rate band" do
    create_complete_week(start_weight: 80, end_weight: 80.8)

    review = WeeklyEvidenceReview.new(@user, period_end: @period_end).call

    assert_equal "adjust_calories", review.output["status"]
    assert_equal "decrease", review.output["calorie_direction"]
    assert_operator review.output["weight_rate_pct_per_week"], :>, 0.5
    assert_equal 7, review.output.dig("evidence", "nutrition_days")
    assert_equal 7, review.output.dig("evidence", "weight_trend_days")
    assert_equal 14, review.child_links.count
    assert_equal %w[nutrition readiness], review.child_links.distinct.pluck(:role).sort
  end

  test "refuses to correct calories without a full evidence window" do
    create_nutrition_decision(@period_end, status: "on_track")
    create_weight_trend(@period_end, 80)

    review = WeeklyEvidenceReview.new(@user, period_end: @period_end).call

    assert_equal "insufficient_evidence", review.output["status"]
    assert_equal "insufficient_evidence", review.output["calorie_direction"]
    assert_equal "low", review.confidence
  end

  test "reuses the immutable review when its evidence is unchanged" do
    create_complete_week(start_weight: 80, end_weight: 80.3)
    first = WeeklyEvidenceReview.new(@user, period_end: @period_end).call

    assert_no_difference [ "CoachingDecision.count", "CoachingDecisionLink.count" ] do
      assert_equal first, WeeklyEvidenceReview.new(@user, period_end: @period_end).call
    end
  end

  test "defaults to the last completed calendar week in the user's time zone" do
    @user.update!(time_zone: "America/Denver")

    travel_to Time.utc(2026, 6, 10, 5, 30) do
      review = WeeklyEvidenceReview.new(@user).call

      assert_equal "2026-06-07", review.inputs["period_end"]
      assert_equal "2026-06-01", review.inputs["period_start"]
    end
  end

  private

  def create_complete_week(start_weight:, end_weight:)
    7.times do |index|
      date = @period_end - (6 - index).days
      weight = start_weight + ((end_weight - start_weight) * index / 6.0)
      create_readiness_decision(date, 78 + index)
      create_nutrition_decision(date, status: "on_track")
      create_weight_trend(date, weight)
    end
  end

  def create_readiness_decision(date, score)
    @user.coaching_decisions.create!(
      decision_type: "daily_readiness",
      rule_key: ReadinessEvaluator::RULE_KEY,
      rule_version: "1.0.0",
      inputs: { "metric_date" => date.iso8601 },
      output: { "status" => "push", "readiness_score" => score },
      citations: [],
      confidence: "high"
    )
  end

  def create_nutrition_decision(date, status:)
    @user.coaching_decisions.create!(
      decision_type: "daily_nutrition",
      rule_key: NutritionEvaluator::RULE_KEY,
      rule_version: "1.0.0",
      inputs: { "nutrition_date" => date.iso8601 },
      output: {
        "status" => status,
        "totals" => { "kcal" => 2_800, "protein_g" => 180 },
        "targets" => { "kcal" => 2_800, "protein_g" => 180 }
      },
      citations: [],
      confidence: "high"
    )
  end

  def create_weight_trend(date, weight)
    @user.weight_trends.create!(
      trend_date: date,
      raw_kg: weight,
      ewma_kg: weight
    )
  end
end
