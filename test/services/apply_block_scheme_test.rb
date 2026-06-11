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
    count = ApplyBlockScheme.new(@user, focus: "strength").call

    assert_equal 2, count

    @squat_target.reload # strength compound: 3-5 reps, 4 sets
    assert_equal 3, @squat_target.rep_min
    assert_equal 5, @squat_target.rep_max
    assert_equal 4, @squat_target.working_sets

    @curl_target.reload # strength isolation: 6-8 reps, 3 sets
    assert_equal 6, @curl_target.rep_min
    assert_equal 8, @curl_target.rep_max
    assert_equal 3, @curl_target.working_sets
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
      increment_kg: 2.5, working_sets: 3, started_on: Date.current
    )
  end
end
