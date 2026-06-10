require "test_helper"

class WorkoutLogPrefillTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Bench Press", modality: "barbell")
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

  test "prefills prescribed sets from the latest progression target and prior actuals" do
    prior_workout = @user.workout_sessions.create!(performed_at: 1.day.ago)
    [ 8, 8, 7 ].each_with_index do |reps, index|
      prior_workout.set_entries.create!(
        exercise: @exercise,
        set_index: index + 1,
        weight_kg: 100,
        reps:,
        rir: 1
      )
    end
    CoachingDecision.create!(
      user: @user,
      decision_type: "double_progression",
      rule_key: DoubleProgressionEvaluator::RULE_KEY,
      rule_version: DoubleProgressionEvaluator::RULE_VERSION,
      inputs: {
        "exercise_id" => @exercise.id,
        "prescription" => { "id" => @prescription.id }
      },
      output: { "next_weight_kg" => 102.5 },
      citations: [],
      confidence: "high"
    )

    workout = @user.workout_sessions.new(performed_at: Time.current)
    contexts = WorkoutLogPrefill.new(@user, workout_session: workout, log_date: Date.current).call

    assert_equal 3, contexts.size
    assert_equal [ 102.5, 102.5, 102.5 ], contexts.map { |context| context.entry.weight_kg.to_f }
    assert_equal [ 8, 8, 8 ], contexts.map { |context| context.entry.reps }
    assert_equal [ 8, 8, 7 ], contexts.map { |context| context.last_set.reps }
  end
end
