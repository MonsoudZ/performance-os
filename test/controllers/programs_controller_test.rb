require "test_helper"

class ProgramsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    ExerciseCatalogImporter.new.call
  end

  test "generates a program from the goal and recomputes the plan" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: @user.local_date)

    assert_difference "@user.exercise_prescriptions.active.count", 10 do
      assert_enqueued_with(job: TrainingPlanRecomputeJob) do
        post program_path
      end
    end

    assert_redirected_to exercise_prescriptions_path
    assert_match(/starting program/, flash[:notice])
  end

  test "without a goal it sends you to set one" do
    assert_no_difference "ExercisePrescription.count" do
      post program_path
    end

    assert_redirected_to goal_periods_path
    assert_match(/goal/, flash[:alert])
  end

  test "refresh retires unavailable lifts and recomputes the plan" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: @user.local_date)
    post program_path # build the full program first
    @user.update!(available_equipment: %w[dumbbell machine cable bodyweight])

    assert_enqueued_with(job: TrainingPlanRecomputeJob) do
      patch program_path
    end

    assert_redirected_to exercise_prescriptions_path
    assert_match(/Refreshed/, flash[:notice])
    assert_equal 0, @user.exercise_prescriptions.active.joins(:exercise).where(exercises: { modality: "barbell" }).count
  end

  test "refresh without a goal sends you to set one" do
    patch program_path
    assert_redirected_to goal_periods_path
  end

  test "re-running when the program is already built adds nothing" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: @user.local_date)
    post program_path

    assert_no_difference "ExercisePrescription.count" do
      post program_path
    end

    assert_redirected_to exercise_prescriptions_path
    assert_match(/already covers/, flash[:notice])
  end
end
