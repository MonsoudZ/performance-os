require "test_helper"

class WorkoutSessionTest < ActiveSupport::TestCase
  test "template snapshot keeps historical name and completion plan" do
    user = users(:one)
    exercise = Exercise.create!(name: "Overhead Press", modality: "barbell")
    template = user.workout_templates.create!(
      name: "Push",
      weekdays: [ Date.current.wday ],
      workout_template_exercises_attributes: {
        "0" => { exercise:, position: 1 }
      }
    )
    session = user.workout_sessions.create!(
      workout_template: template,
      performed_at: Time.current,
      template_snapshot: {
        "name" => "Push",
        "exercises" => [
          { "exercise_id" => exercise.id, "exercise_name" => exercise.name, "working_sets" => 3 }
        ]
      }
    )
    session.set_entries.create!(exercise:, set_index: 1, weight_kg: 50, reps: 8, rir: 1)
    session.set_entries.create!(exercise:, set_index: 2, weight_kg: 50, reps: 8, rir: 1)

    template.update!(name: "Push A")

    assert_equal "Push", session.reload.template_name
    assert_equal 3, session.planned_working_sets
    assert_equal 2, session.completed_working_sets
    assert_equal 67, session.completion_percentage
  end
end
