require "test_helper"

class ApplyBlockSchemeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @squat = Exercise.create!(name: "Back Squat", modality: "barbell", is_compound: true)
    @curl = Exercise.create!(name: "Biceps Curl", modality: "dumbbell", is_compound: false)
    @squat_target = prescription_for(@squat)
    @curl_target = prescription_for(@curl)
  end

  test "applies the compound variant to compounds and the isolation variant to isolations" do
    assert_difference "ExercisePrescription.count", 2 do
      assert_equal 2, ApplyBlockScheme.new(@user, focus: "strength").call
    end

    assert_equal Date.current - 1.day, @squat_target.reload.ended_on
    assert_equal 8, @squat_target.rep_min
    assert_equal 12, @squat_target.rep_max
    assert_equal 3, @squat_target.working_sets

    squat_replacement = @user.exercise_prescriptions.active.find_by!(exercise: @squat)
    assert_equal Date.current, squat_replacement.started_on
    assert_equal 3, squat_replacement.rep_min
    assert_equal 5, squat_replacement.rep_max
    assert_equal 4, squat_replacement.working_sets

    curl_replacement = @user.exercise_prescriptions.active.find_by!(exercise: @curl)
    assert_equal 6, curl_replacement.rep_min
    assert_equal 8, curl_replacement.rep_max
    assert_equal 3, curl_replacement.working_sets
  end

  test "leaves ended targets untouched" do
    @curl_target.update!(ended_on: Date.current)

    assert_equal 1, ApplyBlockScheme.new(@user, focus: "strength").call
    assert_equal 12, @curl_target.reload.rep_max # original, unchanged
  end

  private

  def prescription_for(exercise)
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 8, rep_max: 12, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current - 7.days
    )
  end
end
