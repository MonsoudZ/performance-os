require "application_system_test_case"

# The whole point of the feature is the second time being cheaper than the
# first, so the test walks it: log a workout, save it, and find it waiting under
# Workouts ready to run again.
class SavingASessionAsAWorkoutTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @squat = Exercise.create!(name: "Zzz Sys Squat", modality: "barbell", is_compound: true)
    @row = Exercise.create!(name: "Zzz Sys Row", modality: "barbell", is_compound: true)
    @session = @user.workout_sessions.create!(performed_at: 1.hour.ago)
    @session.set_entries.create!(exercise: @squat, set_index: 1, weight_kg: 100, reps: 5, rir: 2)
    @session.set_entries.create!(exercise: @row, set_index: 2, weight_kg: 70, reps: 8, rir: 2)
  end

  test "a logged session becomes a workout you can run again" do
    sign_in @user
    visit workout_session_path(@session)

    assert_text "Save as a workout"
    fill_in "Name", with: "Zzz Sys Pull Day"
    click_on "Save as a workout"

    # Lands in the editor, where scheduling it to a day is the one thing the
    # session could not supply.
    assert_text "Zzz Sys Pull Day"
    assert_current_path edit_workout_template_path(@user.workout_templates.find_by(name: "Zzz Sys Pull Day"))

    visit workout_templates_path
    assert_text "Zzz Sys Pull Day"
    assert_text "Zzz Sys Squat"
    assert_text "Zzz Sys Row"
  end

  # A session with nothing logged would make an invalid workout, so it is not
  # offered rather than offered and refused.
  test "an empty session is not offered" do
    empty = @user.workout_sessions.create!(performed_at: 2.hours.ago)
    sign_in @user

    visit workout_session_path(empty)

    assert_no_text "Save as a workout"
  end
end
