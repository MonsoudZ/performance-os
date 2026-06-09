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
end
