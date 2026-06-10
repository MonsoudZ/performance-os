require "test_helper"

class WorkoutSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @exercise = Exercise.create!(name: "Back Squat", modality: "barbell")
    ExercisePrescription.create!(
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

  test "logs working sets and creates a progression decision" do
    assert_difference "WorkoutSession.count", 1 do
      assert_difference "SetEntry.count", 3 do
        assert_difference "CoachingDecision.count", 1 do
          post workout_sessions_path, params: {
            workout_session: {
              performed_at: Time.current,
              set_entries_attributes: {
                "0" => set_params(1),
                "1" => set_params(2),
                "2" => set_params(3)
              }
            }
          }
        end
      end
    end

    assert_redirected_to workout_session_path(WorkoutSession.last)
    assert_equal "increase", CoachingDecision.last.output["status"]
  end

  test "new workout renders prescribed set count instead of fixed blank rows" do
    get new_workout_session_path

    assert_response :success
    assert_select "[data-workout-log-target='rows'] > [data-workout-log-target='row']", count: 3
    assert_select "input[value='8']", minimum: 3
    assert_select "[data-workout-log-target='volume']", text: "0 kg"
  end

  test "does not expose another user's workout" do
    other_workout = users(:two).workout_sessions.create!(performed_at: Time.current)

    get workout_session_path(other_workout)

    assert_response :not_found
  end

  test "rejects another user's custom exercise in nested sets" do
    foreign_exercise = Exercise.create!(user: users(:two), name: "Private Lift", modality: "other")

    assert_no_difference [ "WorkoutSession.count", "SetEntry.count" ] do
      post workout_sessions_path, params: {
        workout_session: {
          performed_at: Time.current,
          set_entries_attributes: {
            "0" => set_params(1).merge(exercise_id: foreign_exercise.id)
          }
        }
      }
    end

    assert_response :unprocessable_entity
  end

  private

  def set_params(index)
    {
      exercise_id: @exercise.id,
      set_index: index,
      weight_kg: 100,
      reps: 8,
      rir: 1
    }
  end
end
