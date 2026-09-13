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

  test "editing a historical target supersedes it effective today" do
    exercise = Exercise.create!(user: @user, name: "Overhead Press", modality: "barbell")
    prescription = prescription_for(exercise, started_on: Date.current - 10.days)

    assert_difference "ExercisePrescription.count", 1 do
      assert_enqueued_with(job: TrainingPlanRecomputeJob) do
        patch exercise_prescription_path(prescription),
          params: { exercise_prescription: prescription_attributes(exercise).merge(rep_max: 10) }
      end
    end

    assert_equal 8, prescription.reload.rep_max
    assert_equal Date.current - 1.day, prescription.ended_on
    replacement = @user.exercise_prescriptions.active.find_by!(exercise: exercise)
    assert_equal Date.current, replacement.started_on
    assert_equal 10, replacement.rep_max
    assert_redirected_to exercise_prescriptions_path
  end

  test "editing a target created today corrects it without creating duplicate history" do
    exercise = Exercise.create!(user: @user, name: "Paused Squat", modality: "barbell")
    prescription = prescription_for(exercise)

    assert_no_difference "ExercisePrescription.count" do
      patch exercise_prescription_path(prescription),
        params: { exercise_prescription: prescription_attributes(exercise).merge(rep_max: 10) }
    end

    assert_equal 10, prescription.reload.rep_max
  end

  test "an invalid historical edit leaves the current target active" do
    exercise = Exercise.create!(user: @user, name: "Tempo Squat", modality: "barbell")
    prescription = prescription_for(exercise, started_on: Date.current - 10.days)

    assert_no_difference "ExercisePrescription.count" do
      patch exercise_prescription_path(prescription),
        params: {
          exercise_prescription: prescription_attributes(exercise).merge(
            rep_min: 10,
            rep_max: 5
          )
        }
    end

    assert_response :unprocessable_entity
    assert_nil prescription.reload.ended_on
    assert_equal 8, prescription.rep_max
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

  test "the edit form offers to opt a target out of the active block" do
    @user.mesocycles.create!(focus: "strength", started_on: Date.current - 2, weeks: 4)
    prescription = prescription_for(compound_exercise)

    get edit_exercise_prescription_path(prescription)

    assert_response :success
    assert_select "input[name='exercise_prescription[follows_block_scheme]'][type=checkbox]"
    assert_select "label", { text: /strength block/ }, "the checkbox has to name the block it opts out of"
  end

  test "no block means nothing to opt out of" do
    prescription = prescription_for(compound_exercise)

    get edit_exercise_prescription_path(prescription)

    assert_response :success
    assert_select "input[name='exercise_prescription[follows_block_scheme]'][type=checkbox]", 0
  end

  test "opting out holds the target to its own numbers inside the block" do
    @user.mesocycles.create!(focus: "strength", started_on: Date.current - 2, weeks: 4)
    exercise = compound_exercise
    prescription = prescription_for(exercise)

    get exercise_prescriptions_path
    assert_select ".prescription-card strong", text: /3–5/

    patch exercise_prescription_path(prescription), params: {
      exercise_prescription: prescription_attributes(exercise).merge(follows_block_scheme: "0")
    }

    get exercise_prescriptions_path
    assert_select ".prescription-card strong", text: /6–8/
  end

  test "the index says when a target's numbers are the block's" do
    @user.mesocycles.create!(focus: "power", started_on: Date.current - 2, weeks: 4)
    prescription_for(compound_exercise)

    get exercise_prescriptions_path

    assert_response :success
    assert_select ".prescription-card small", text: /From the power block/
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

  def compound_exercise
    Exercise.create!(user: @user, name: "Zzz Scheme Press", modality: "barbell", is_compound: true)
  end

  def prescription_for(exercise, started_on: Date.current)
    @user.exercise_prescriptions.create!(
      exercise: exercise,
      rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: started_on
    )
  end
end
