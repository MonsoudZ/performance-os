require "test_helper"

class DoubleProgressionEvaluatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Bench Press", modality: "barbell", is_compound: true)
    @prescription = ExercisePrescription.create!(
      user: @user,
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

  test "increases load when every prescribed set hits the top range at target RIR" do
    workout = create_workout([ [ 100, 8, 2 ], [ 100, 8, 1 ], [ 100, 8, 1 ] ])

    decision = DoubleProgressionEvaluator.new(workout).call.first

    assert_equal "increase", decision.output["status"]
    assert_equal 102.5, decision.output["next_weight_kg"]
    assert_equal "high", decision.confidence
    assert_equal "double_progression.v1", decision.rule_key
  end

  test "holds load until all sets reach the top range" do
    workout = create_workout([ [ 100, 8, 2 ], [ 100, 7, 2 ], [ 100, 6, 1 ] ])

    decision = DoubleProgressionEvaluator.new(workout).call.first

    assert_equal "hold", decision.output["status"]
    assert_equal 100.0, decision.output["next_weight_kg"]
  end

  test "does not make a progression call from an incomplete prescription" do
    workout = create_workout([ [ 100, 8, 2 ], [ 100, 8, 1 ] ])

    decision = DoubleProgressionEvaluator.new(workout).call.first

    assert_equal "insufficient", decision.output["status"]
    assert_equal "low", decision.confidence
  end

  test "deloads after three distinct stalled sessions at the same load" do
    2.times do
      decision = DoubleProgressionEvaluator.new(
        create_workout([ [ 100, 8, 2 ], [ 100, 8, 2 ], [ 100, 7, 1 ] ])
      ).call.first
      assert_equal "hold", decision.output["status"]
    end

    decision = DoubleProgressionEvaluator.new(
      create_workout([ [ 100, 8, 2 ], [ 100, 8, 2 ], [ 100, 7, 1 ] ])
    ).call.first

    assert_equal "deload", decision.output["status"]
    assert_equal 90, decision.output["next_weight_kg"]
    assert_equal 3, decision.output["stall_sessions"]
  end

  test "does not count duplicate decisions from one workout as separate stalls" do
    workout = create_workout([ [ 100, 8, 2 ], [ 100, 8, 2 ], [ 100, 7, 1 ] ])
    2.times { DoubleProgressionEvaluator.new(workout).call }

    decision = DoubleProgressionEvaluator.new(
      create_workout([ [ 100, 8, 2 ], [ 100, 8, 2 ], [ 100, 7, 1 ] ])
    ).call.first

    assert_equal "hold", decision.output["status"]
  end

  test "requires stalled sessions to be consecutive" do
    first_hold = create_workout([ [ 100, 8, 2 ], [ 100, 8, 2 ], [ 100, 7, 1 ] ])
    DoubleProgressionEvaluator.new(first_hold).call
    successful = create_workout([ [ 100, 8, 2 ], [ 100, 8, 1 ], [ 100, 8, 1 ] ])
    DoubleProgressionEvaluator.new(successful).call

    decision = DoubleProgressionEvaluator.new(
      create_workout([ [ 100, 8, 2 ], [ 100, 8, 2 ], [ 100, 7, 1 ] ])
    ).call.first

    assert_equal "hold", decision.output["status"]
  end

  test "top-set model progresses on the heaviest set even with lighter back-offs" do
    @prescription.update!(progression_model: "top_set")
    # A ramp to a top set of 105 with back-off sets — the straight-set model
    # would hold on the inconsistent load, the top-set model progresses.
    workout = create_workout([ [ 105, 8, 1 ], [ 95, 8, 2 ], [ 95, 8, 2 ] ])

    decision = DoubleProgressionEvaluator.new(workout).call.first

    assert_equal "increase", decision.output["status"]
    assert_equal 105.0, decision.output["current_weight_kg"]
    assert_equal 107.5, decision.output["next_weight_kg"]
    assert_equal "top_set", decision.inputs.dig("prescription", "progression_model")
    assert_equal "double_progression.v1", decision.rule_key
  end

  test "top-set model holds when the top set misses the rep ceiling" do
    @prescription.update!(progression_model: "top_set")
    workout = create_workout([ [ 105, 7, 2 ], [ 95, 8, 2 ], [ 95, 8, 2 ] ])

    decision = DoubleProgressionEvaluator.new(workout).call.first

    assert_equal "hold", decision.output["status"]
    assert_equal 105.0, decision.output["next_weight_kg"]
    assert_match(/top set/i, decision.output["guidance"])
  end

  test "straight-set model still holds on a ramp to the top weight" do
    # Same sets as the top-set increase case, but the default straight-set model
    # refuses to progress because the working load was not consistent.
    workout = create_workout([ [ 105, 8, 1 ], [ 95, 8, 2 ], [ 95, 8, 2 ] ])

    decision = DoubleProgressionEvaluator.new(workout).call.first

    assert_equal "hold", decision.output["status"]
    assert_match(/consistent/i, decision.output["guidance"])
  end

  private

  def create_workout(set_values)
    workout = @user.workout_sessions.create!(performed_at: Time.current)
    set_values.each_with_index do |(weight, reps, rir), index|
      workout.set_entries.create!(
        exercise: @exercise,
        set_index: index + 1,
        weight_kg: weight,
        reps: reps,
        rir: rir
      )
    end
    workout
  end
end
