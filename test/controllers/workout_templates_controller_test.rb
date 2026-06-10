require "test_helper"

class WorkoutTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @squat = Exercise.create!(name: "Back Squat", modality: "barbell")
    @bench = Exercise.create!(name: "Bench Press", modality: "barbell")
  end

  test "creates a scheduled ordered workout" do
    assert_difference "WorkoutTemplate.count", 1 do
      assert_difference "WorkoutTemplateExercise.count", 2 do
        post workout_templates_path, params: {
          workout_template: {
            name: "Upper",
            weekdays: [ "1", "4" ],
            workout_template_exercises_attributes: {
              "0" => { exercise_id: @bench.id, position: 99 },
              "1" => { exercise_id: @squat.id, position: 99 }
            }
          }
        }
      end
    end

    template = WorkoutTemplate.last
    assert_equal [ 1, 4 ], template.weekdays
    assert_equal [ @bench.id, @squat.id ], template.workout_template_exercises.pluck(:exercise_id)
    assert_redirected_to workout_templates_path
  end

  test "rejects another user's custom exercise" do
    foreign_exercise = Exercise.create!(user: users(:two), name: "Private Press", modality: "other")

    assert_no_difference [ "WorkoutTemplate.count", "WorkoutTemplateExercise.count" ] do
      post workout_templates_path, params: {
        workout_template: {
          name: "Unsafe",
          weekdays: [ "2" ],
          workout_template_exercises_attributes: {
            "0" => { exercise_id: foreign_exercise.id, position: 1 }
          }
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "reorders existing exercises without rewriting the workout" do
    template = @user.workout_templates.create!(
      name: "Strength",
      workout_template_exercises_attributes: {
        "0" => { exercise: @squat, position: 1 },
        "1" => { exercise: @bench, position: 2 }
      }
    )
    squat_item, bench_item = template.workout_template_exercises.to_a

    assert_no_difference [ "WorkoutTemplate.count", "WorkoutTemplateExercise.count" ] do
      patch workout_template_path(template), params: {
        workout_template: {
          name: "Strength",
          weekdays: [ "3" ],
          workout_template_exercises_attributes: {
            "0" => { id: bench_item.id, exercise_id: @bench.id, position: 1 },
            "1" => { id: squat_item.id, exercise_id: @squat.id, position: 2 }
          }
        }
      }
    end

    assert_redirected_to workout_templates_path
    assert_equal [ @bench.id, @squat.id ], template.reload.workout_template_exercises.pluck(:exercise_id)
  end

  test "does not expose another user's workout template" do
    foreign_template = users(:two).workout_templates.create!(
      name: "Private Day",
      workout_template_exercises_attributes: {
        "0" => { exercise: @squat, position: 1 }
      }
    )

    get edit_workout_template_path(foreign_template)

    assert_response :not_found
  end
end
