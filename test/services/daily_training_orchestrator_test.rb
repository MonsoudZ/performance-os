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

  test "ignores a retracted progression decision when recomposing the plan" do
    create_readiness_decision("push", 88, "high")
    progression = create_progression_decision("increase", 102.5, "high")
    first_parent = DailyTrainingOrchestrator.new(@user).call
    progression.retract!(reason: "workout_session_deleted")

    second_parent = DailyTrainingOrchestrator.new(@user).call

    assert_not_equal first_parent, second_parent
    assert_equal "establish", second_parent.output["lifts"].first["action"]
    assert_nil second_parent.output["lifts"].first["progression_decision_id"]
    assert_empty second_parent.child_links.where(role: "progression")
  end

  test "treats a retracted readiness decision as missing and writes no plan" do
    readiness = create_readiness_decision("push", 88, "high")
    assert DailyTrainingOrchestrator.new(@user).call

    readiness.retract!(reason: "readiness_corrected")

    assert_nil DailyTrainingOrchestrator.new(@user).call
  end

  test "superseding a target resets the day's plan to a fresh progression baseline" do
    @prescription.update!(started_on: Date.current - 10.days)
    create_readiness_decision("push", 88, "high")
    create_progression_decision("increase", 102.5, "high")

    earned = DailyTrainingOrchestrator.new(@user).call
    assert_equal "increase", earned.output["lifts"].first["action"]

    ExercisePrescriptionSuperseder.new(@prescription, effective_on: Date.current).call(rep_max: 10)

    rebaselined = DailyTrainingOrchestrator.new(@user).call

    assert_not_equal earned, rebaselined
    lift = rebaselined.output["lifts"].first
    assert_equal "establish", lift["action"]
    assert_nil lift["progression_decision_id"]
    assert_empty rebaselined.child_links.where(role: "progression")
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

  test "a deload week backs off the lifts and headline even when readiness is high" do
    create_readiness_decision("push", 90, "high")
    create_progression_decision("increase", 102.5, "high")
    # Started 21 days ago -> today is week 4, the scheduled deload.
    @user.mesocycles.create!(started_on: Date.current - 21.days, weeks: 4, deload_week: 4)

    parent = DailyTrainingOrchestrator.new(@user).call
    lift = parent.output["lifts"].first

    assert_equal "deload", lift["action"]
    assert_match(/Deload week/i, parent.output["headline"])
    assert parent.output.dig("mesocycle", "deload")
    assert_equal 4, parent.output.dig("mesocycle", "week")
  end

  test "ramps accumulation volume week over week" do
    create_readiness_decision("push", 88, "high")
    create_progression_decision("increase", 102.5, "high")
    # 14 days in -> week 3 of a 4-week block (deload week 4): accumulation, +2 sets.
    @user.mesocycles.create!(started_on: Date.current - 14.days, weeks: 4, deload_week: 4)

    lift = DailyTrainingOrchestrator.new(@user).call.output["lifts"].first

    assert_equal 5, lift["working_sets"] # baseline 3 + 2
    assert_match(/Volume ramp/i, lift["guidance"])
  end

  test "a strength block caps the volume ramp and carries its focus into the plan" do
    create_readiness_decision("push", 88, "high")
    create_progression_decision("increase", 102.5, "high")
    # Week 5 of a strength block — hypertrophy would add +4, strength caps at +1.
    @user.mesocycles.create!(started_on: Date.current - 28.days, weeks: 6, deload_week: 6, focus: "strength")

    output = DailyTrainingOrchestrator.new(@user).call.output

    assert_equal 4, output["lifts"].first["working_sets"] # baseline 3 + 1
    assert_equal "strength", output.dig("mesocycle", "focus")
    assert_match(/Strength/i, output.dig("mesocycle", "emphasis"))
  end

  test "week one of accumulation uses baseline volume" do
    create_readiness_decision("push", 88, "high")
    create_progression_decision("increase", 102.5, "high")
    @user.mesocycles.create!(started_on: Date.current, weeks: 4, deload_week: 4) # week 1

    lift = DailyTrainingOrchestrator.new(@user).call.output["lifts"].first

    assert_equal 3, lift["working_sets"]
    assert_no_match(/Volume ramp/i, lift["guidance"])
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
        "exercise_name" => @exercise.name,
        "prescription" => { "id" => @prescription.id }
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
