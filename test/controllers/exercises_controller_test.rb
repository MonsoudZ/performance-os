require "test_helper"

class ExercisesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "renders the new custom exercise form" do
    get new_exercise_path

    assert_response :success
    assert_select "h1", "Add a custom exercise."
  end

  test "creates a user-owned exercise" do
    assert_difference "Exercise.count", 1 do
      post exercises_path, params: {
        exercise: { name: "Spanish Squat", modality: "machine", default_unit: "kg", is_compound: true }
      }
    end

    exercise = Exercise.order(:id).last
    assert_equal @user, exercise.user
    assert_equal "Spanish Squat", exercise.name
    assert exercise.is_compound
    assert_redirected_to new_exercise_prescription_path
  end

  test "rejects an invalid modality" do
    assert_no_difference "Exercise.count" do
      post exercises_path, params: {
        exercise: { name: "Mystery Lift", modality: "telekinesis", default_unit: "kg" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "the new exercise becomes available to prescribe" do
    post exercises_path, params: {
      exercise: { name: "Hatfield Squat", modality: "barbell", default_unit: "kg" }
    }

    assert_includes Exercise.available_to(@user).pluck(:name), "Hatfield Squat"
  end
end
