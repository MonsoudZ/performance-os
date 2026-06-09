require "test_helper"

class ReadinessEvaluatorTest < ActiveSupport::TestCase
  test "creates an auditable push recommendation for strong recovery" do
    user = User.create!(email_address: "ready@example.com", password: "password")
    readiness_input = user.daily_readiness_inputs.create!(
      metric_date: Date.current,
      sleep_minutes: 480,
      sleep_quality: 5,
      soreness: 1,
      fatigue: 1,
      stress: 2
    )

    score, decision = ReadinessEvaluator.new(readiness_input).call

    assert_operator score.score, :>=, 75
    assert_equal "push", decision.output["status"]
    assert_equal "daily_readiness", decision.decision_type
    assert_equal "daily_readiness.v1", decision.rule_key
    assert_equal "high", decision.confidence
  end

  test "recommends recovery when inputs are poor" do
    user = User.create!(email_address: "tired@example.com", password: "password")
    readiness_input = user.daily_readiness_inputs.create!(
      metric_date: Date.current,
      sleep_minutes: 300,
      sleep_quality: 1,
      soreness: 5,
      fatigue: 5,
      stress: 5
    )

    score, decision = ReadinessEvaluator.new(readiness_input).call

    assert_operator score.score, :<, 50
    assert_equal "recover", decision.output["status"]
  end

  test "is idempotent for unchanged readiness evidence" do
    user = User.create!(email_address: "stable@example.com", password: "password")
    readiness_input = user.daily_readiness_inputs.create!(
      metric_date: Date.current,
      sleep_minutes: 450,
      sleep_quality: 4,
      soreness: 2,
      fatigue: 2,
      stress: 2
    )
    first_score, first_decision = ReadinessEvaluator.new(readiness_input).call

    assert_no_difference [ "ReadinessScore.count", "CoachingDecision.count" ] do
      score, decision = ReadinessEvaluator.new(readiness_input).call
      assert_equal first_score.score, score.score
      assert_equal first_score.score_date, score.score_date
      assert_equal first_decision, decision
    end
  end

  test "replaces the daily score cache and appends a decision when evidence changes" do
    user = User.create!(email_address: "late-sync@example.com", password: "password")
    readiness_input = user.daily_readiness_inputs.create!(
      metric_date: Date.current,
      sleep_minutes: 420,
      fatigue: 3,
      source: "manual"
    )
    _score, first_decision = ReadinessEvaluator.new(readiness_input).call
    readiness_input.update!(sleep_minutes: 480, source: "mixed")

    assert_no_difference "ReadinessScore.count" do
      assert_difference "CoachingDecision.count", 1 do
        score, decision = ReadinessEvaluator.new(readiness_input).call
        assert_equal 480, decision.inputs["sleep_minutes"]
        assert_not_equal first_decision, decision
        assert_equal Date.current, score.score_date
      end
    end
  end
end
