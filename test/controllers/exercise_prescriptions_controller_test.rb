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

  test "creating a target for an already-prescribed exercise retires the old one" do
    exercise = Exercise.create!(user: @user, name: "Romanian Deadlift", modality: "barbell")
    old = prescription_for(exercise, started_on: Date.current - 20.days)

    assert_difference "ExercisePrescription.count", 1 do
      post exercise_prescriptions_path, params: { exercise_prescription: prescription_attributes(exercise) }
    end

    assert_equal Date.current - 1.day, old.reload.ended_on
    assert_equal 1, @user.exercise_prescriptions.active.where(exercise: exercise).count
  end

  test "edits an existing target and enqueues a plan recompute" do
    exercise = Exercise.create!(user: @user, name: "Overhead Press", modality: "barbell")
    prescription = prescription_for(exercise)

    assert_enqueued_with(job: TrainingPlanRecomputeJob) do
      patch exercise_prescription_path(prescription),
        params: { exercise_prescription: prescription_attributes(exercise).merge(rep_max: 10) }
    end

    assert_equal 10, prescription.reload.rep_max
    assert_redirected_to exercise_prescriptions_path
  end

  test "ends a target" do
    exercise = Exercise.create!(user: @user, name: "Barbell Row", modality: "barbell")
    prescription = prescription_for(exercise, started_on: Date.current - 5.days)

    patch finish_exercise_prescription_path(prescription)

    assert_equal Date.current - 1.day, prescription.reload.ended_on
    assert_redirected_to exercise_prescriptions_path
  end

  test "cannot edit another user's target" do
    foreign = users(:two).exercise_prescriptions.create!(
      exercise: Exercise.create!(user: users(:two), name: "Sissy Squat", modality: "machine"),
      rep_min: 8, rep_max: 12, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current
    )

    get edit_exercise_prescription_path(foreign)

    assert_response :not_found
  end

  private

  def prescription_attributes(exercise)
    {
      exercise_id: exercise.id,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      progression_model: "double_progression",
      started_on: Date.current
    }
  end

  def prescription_for(exercise, started_on: Date.current)
    @user.exercise_prescriptions.create!(
      exercise: exercise,
      rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: started_on
    )
  end
end
