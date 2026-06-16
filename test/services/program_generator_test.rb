require "test_helper"

class ProgramGeneratorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    ExerciseCatalogImporter.new.call # populate the shared catalog
  end

  def set_goal(goal_type)
    @user.goal_periods.create!(goal_type: goal_type, started_on: @user.local_date)
  end

  def active_prescription_for(name)
    exercise = Exercise.find_by!(user_id: nil, name: name)
    @user.exercise_prescriptions.active.find_by(exercise: exercise)
  end

  test "builds a balanced program covering the major muscle groups from the goal" do
    set_goal("build_muscle")

    result = nil
    assert_difference "@user.exercise_prescriptions.active.count", 10 do
      result = ProgramGenerator.new(@user).call
    end

    assert_equal "hypertrophy", result.focus
    assert result.created_any?

    # One primary lift per covered group — distinct exercises, no duplicates.
    exercise_ids = @user.exercise_prescriptions.active.pluck(:exercise_id)
    assert_equal exercise_ids.uniq, exercise_ids
    # Spot-check coverage across push / pull / legs.
    assert active_prescription_for("Barbell Back Squat"), "should train quads"
    assert active_prescription_for("Barbell Bench Press"), "should train chest"
    assert active_prescription_for("Barbell Row"), "should train back"
  end

  test "matches the rep scheme to the goal focus" do
    set_goal("build_muscle")
    ProgramGenerator.new(@user).call
    squat = active_prescription_for("Barbell Back Squat")
    # Hypertrophy compound: 6-10 reps, 1-2 RIR, 3 sets.
    assert_equal [ 6, 10, 3 ], [ squat.rep_min, squat.rep_max, squat.working_sets ]

    other = users(:two)
    other.goal_periods.create!(goal_type: "increase_strength", started_on: other.local_date)
    ProgramGenerator.new(other).call
    strength_squat = other.exercise_prescriptions.active.find_by!(
      exercise: Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    )
    # Strength compound: 3-5 reps, 4 sets.
    assert_equal [ 3, 5, 4 ], [ strength_squat.rep_min, strength_squat.rep_max, strength_squat.working_sets ]
  end

  test "is idempotent and never clobbers an existing target" do
    set_goal("build_muscle")
    squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    manual = @user.exercise_prescriptions.create!(
      exercise: squat, rep_min: 5, rep_max: 5, target_rir_min: 0, target_rir_max: 1,
      increment_kg: 5, working_sets: 5, started_on: @user.local_date
    )

    ProgramGenerator.new(@user).call
    count_after_first = @user.exercise_prescriptions.active.count

    assert_no_difference "@user.exercise_prescriptions.active.count" do
      ProgramGenerator.new(@user).call
    end

    # The manual squat target is untouched (one active squat, still 5x5).
    assert_equal 1, @user.exercise_prescriptions.active.where(exercise: squat).count
    assert_equal [ 5, 5, 5 ], [ manual.reload.rep_min, manual.rep_max, manual.working_sets ]
    assert_operator count_after_first, :>=, 8
  end

  test "does nothing without an active goal" do
    assert_no_difference [ "ExercisePrescription.count", "Mesocycle.count" ] do
      result = ProgramGenerator.new(@user).call
      assert_nil result.goal
      assert_not result.created_any?
    end
  end

  test "starts a block matching the focus, but leaves an active block alone" do
    set_goal("increase_strength")
    assert_difference "@user.mesocycles.count", 1 do
      ProgramGenerator.new(@user).call
    end
    assert_equal "strength", @user.mesocycles.order(:created_at).last.focus

    # Re-running with a block already active adds no second block.
    assert_no_difference "@user.mesocycles.count" do
      ProgramGenerator.new(@user).call
    end
  end
end
