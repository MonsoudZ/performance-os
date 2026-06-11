require "test_helper"

class DailyTrainingOrchestratorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @goal = @user.goal_periods.create!(
      goal_type: "increase_strength",
      started_on: Date.current
    )
    @exercise = Exercise.create!(name: "Front Squat", modality: "barbell")
    @prescription = @user.exercise_prescriptions.create!(
      exercise: @exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      started_on: Date.current
    )
  end

  test "composes readiness and progression into one auditable daily decision" do
    readiness = create_readiness_decision("push", 88, "high")
    progression = create_progression_decision("increase", 102.5, "high")
    nutrition = create_nutrition_decision

    parent = DailyTrainingOrchestrator.new(@user).call

    assert_equal "daily_training", parent.decision_type
    assert_equal "daily_training_orchestrator.v1", parent.rule_key
    assert_equal "Use the progress you’ve earned", parent.output["headline"]
    assert_equal "102.5 kg", parent.output["lifts"].first["headline"]
    assert_equal "Close the protein gap", parent.output.dig("nutrition", "headline")
    assert_equal [ readiness.id, progression.id, nutrition.id ].sort, parent.child_decisions.pluck(:id).sort
    assert_equal %w[nutrition progression readiness], parent.child_links.pluck(:role).sort
  end

  test "readiness constrains execution without rewriting progression" do
    create_readiness_decision("recover", 34, "high")
    progression = create_progression_decision("increase", 102.5, "high")

    parent = DailyTrainingOrchestrator.new(@user).call
    lift = parent.output["lifts"].first

    assert_equal "recover", parent.output["status"]
    assert_equal "reduce", lift["action"]
    assert_match "Keep the current load", lift["guidance"]
    assert_equal "increase", progression.reload.output["status"]
  end

  test "returns no parent decision without today's readiness child" do
    assert_no_difference "CoachingDecision.count" do
      assert_nil DailyTrainingOrchestrator.new(@user).call
    end
  end

  test "reuses the immutable parent when its composition has not changed" do
    create_readiness_decision("push", 88, "high")
    create_progression_decision("increase", 102.5, "high")
    first_parent = DailyTrainingOrchestrator.new(@user).call

    assert_no_difference [ "CoachingDecision.count", "CoachingDecisionLink.count" ] do
      assert_equal first_parent, DailyTrainingOrchestrator.new(@user).call
    end
  end

  test "composes a conditioning directive from the goal and the week's progress" do
    create_readiness_decision("steady", 60, "moderate")
    @user.update!(max_hr: 190)
    @user.conditioning_sessions.create!(
      activity_type: "run", performed_at: Time.current,
      duration_seconds: 1800, distance_meters: 5000, avg_hr_bpm: 125
    ) # 30 min in Zone 2

    conditioning = DailyTrainingOrchestrator.new(@user).call.output["conditioning"]

    assert conditioning, "expected a conditioning directive in the plan"
    assert_equal "zone2", conditioning["metric"] # increase_strength -> Zone 2 base
    assert_equal 30, conditioning["done"]
    assert_equal 60, conditioning["target"]
  end

  test "regenerates the plan when the week's conditioning changes" do
    create_readiness_decision("steady", 60, "moderate")
    first = DailyTrainingOrchestrator.new(@user).call

    @user.update!(max_hr: 190)
    @user.conditioning_sessions.create!(activity_type: "run", performed_at: Time.current, duration_seconds: 1800, avg_hr_bpm: 125)

    assert_difference "CoachingDecision.count", 1 do
      assert_not_equal first, DailyTrainingOrchestrator.new(@user).call
    end
  end

  private

  def create_readiness_decision(status, score, confidence)
    @user.coaching_decisions.create!(
      decision_type: "daily_readiness",
      rule_key: "daily_readiness.v1",
      rule_version: "1.0.0",
      inputs: { "metric_date" => Date.current.iso8601 },
      output: {
        "status" => status,
        "headline" => "Readiness child",
        "guidance" => "Readiness guidance",
        "readiness_score" => score
      },
      confidence: confidence
    )
  end

  def create_progression_decision(status, next_weight, confidence)
    @user.coaching_decisions.create!(
      decision_type: "double_progression",
      rule_key: "double_progression.v1",
      rule_version: "1.0.0",
      inputs: {
        "exercise_id" => @exercise.id,
        "exercise_name" => @exercise.name
      },
      output: {
        "status" => status,
        "headline" => "Add load",
        "guidance" => "Progression guidance",
        "next_weight_kg" => next_weight
      },
      confidence: confidence
    )
  end

  def create_nutrition_decision
    @user.coaching_decisions.create!(
      decision_type: "daily_nutrition",
      rule_key: "daily_nutrition.v1",
      rule_version: "1.0.0",
      inputs: { "nutrition_date" => Date.current.iso8601 },
      output: {
        "status" => "protein_low",
        "headline" => "Close the protein gap",
        "guidance" => "Eat more protein."
      },
      confidence: "high"
    )
  end
end
