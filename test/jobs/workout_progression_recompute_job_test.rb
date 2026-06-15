require "test_helper"
require "turbo/broadcastable/test_helper"

class WorkoutProgressionRecomputeJobTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Back Squat", modality: "barbell")
    @user.exercise_prescriptions.create!(
      exercise: @exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      started_on: Date.current - 14.days
    )
  end

  # Regression: editing a past workout can retract today's plan, because the
  # plan is composed from that workout's progression decision (the latest
  # evidence for the exercise). The recompute must rebuild today's plan even
  # though the edited workout is not from today.
  test "rebuilds today's plan after editing a past workout retracted it" do
    workout = @user.workout_sessions.create!(performed_at: 3.days.ago)
    3.times do |i|
      workout.set_entries.create!(exercise: @exercise, set_index: i + 1, weight_kg: 100, reps: 8, rir: 1)
    end
    DoubleProgressionEvaluator.new(workout).call
    create_readiness_decision

    plan = DailyTrainingOrchestrator.new(@user).call
    assert plan.child_links.where(role: "progression").exists?,
      "today's plan should be built on the past workout's progression decision"

    WorkoutProgressionRetractor.new(workout, reason: "workout_session_corrected").call
    assert plan.reload.retracted_at, "editing the workout should retract today's plan"

    WorkoutProgressionRecomputeJob.perform_now(workout)

    fresh_plan = @user.coaching_decisions.active_evidence
      .where(decision_type: "daily_training")
      .where("inputs ->> 'plan_date' = ?", @user.local_date.iso8601)
      .order(created_at: :desc)
      .first

    assert fresh_plan, "today's plan should be regenerated after the recompute"
    assert_not_equal plan.id, fresh_plan.id
  end

  private

  def create_readiness_decision
    @user.coaching_decisions.create!(
      decision_type: "daily_readiness",
      rule_key: "daily_readiness.v1",
      rule_version: "1.0.0",
      inputs: { "metric_date" => @user.local_date.iso8601 },
      output: {
        "status" => "push",
        "headline" => "Readiness",
        "guidance" => "Readiness guidance",
        "readiness_score" => 88
      },
      confidence: "high"
    )
  end
end
