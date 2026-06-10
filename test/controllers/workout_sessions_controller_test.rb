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

  test "scheduled template prefills exercises in template order and snapshots the plan" do
    bench = Exercise.create!(name: "Bench Press", modality: "barbell")
    ExercisePrescription.create!(
      user: @user,
      exercise: bench,
      rep_min: 8,
      rep_max: 10,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 2,
      started_on: Date.current
    )
    template = @user.workout_templates.create!(
      name: "Upper",
      weekdays: [ Date.current.wday ],
      workout_template_exercises_attributes: {
        "0" => { exercise: bench, position: 1 },
        "1" => { exercise: @exercise, position: 2 }
      }
    )

    get new_workout_session_path(workout_template_id: template.id)

    assert_response :success
    assert_select "[data-workout-log-target='rows'] > [data-workout-log-target='row']", count: 5
    exercise_names = css_select("[data-workout-log-target='rows'] .set-exercise strong").map(&:text)
    assert_equal [ "Bench Press", "Bench Press", "Back Squat", "Back Squat", "Back Squat" ], exercise_names

    assert_difference "WorkoutSession.count", 1 do
      post workout_sessions_path, params: {
        workout_session: {
          workout_template_id: template.id,
          performed_at: Time.current,
          set_entries_attributes: {
            "0" => set_params(1)
          }
        }
      }
    end

    workout = WorkoutSession.last
    assert_equal template, workout.workout_template
    assert_equal "Upper", workout.template_name
    assert_equal 5, workout.planned_working_sets
  end

  test "does not expose another user's workout" do
    other_workout = users(:two).workout_sessions.create!(performed_at: Time.current)

    get workout_session_path(other_workout)

    assert_response :not_found
  end

  test "does not attach another user's workout template" do
    foreign_template = users(:two).workout_templates.create!(
      name: "Private Day",
      workout_template_exercises_attributes: {
        "0" => { exercise: @exercise, position: 1 }
      }
    )

    post workout_sessions_path, params: {
      workout_session: {
        workout_template_id: foreign_template.id,
        performed_at: Time.current,
        set_entries_attributes: {
          "0" => set_params(1)
        }
      }
    }

    assert_nil WorkoutSession.last.workout_template
    assert_empty WorkoutSession.last.template_snapshot
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
