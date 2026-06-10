require "test_helper"

class ExercisePrescriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "rejects another user's custom exercise" do
    foreign_exercise = Exercise.create!(user: users(:two), name: "Private Curl", modality: "dumbbell")

    assert_no_difference "ExercisePrescription.count" do
      post exercise_prescriptions_path, params: {
        exercise_prescription: {
          exercise_id: foreign_exercise.id,
          rep_min: 8,
          rep_max: 12,
          target_rir_min: 1,
          target_rir_max: 2,
          increment_kg: 2.5,
          working_sets: 3,
          started_on: Date.current
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "creates a prescription with a chosen progression model" do
    exercise = Exercise.create!(user: @user, name: "Front Squat", modality: "barbell")

    assert_difference "ExercisePrescription.count", 1 do
      post exercise_prescriptions_path, params: {
        exercise_prescription: {
          exercise_id: exercise.id,
          rep_min: 4,
          rep_max: 6,
          target_rir_min: 1,
          target_rir_max: 2,
          increment_kg: 2.5,
          working_sets: 4,
          progression_model: "top_set",
          started_on: Date.current
        }
      }
    end

    assert_redirected_to exercise_prescriptions_path
    assert_equal "top_set", ExercisePrescription.last.progression_model
  end
end
