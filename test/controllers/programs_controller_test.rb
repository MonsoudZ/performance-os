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

  test "the notice says why the goal chose the focus it chose" do
    @user.goal_periods.create!(goal_type: "increase_strength", started_on: @user.local_date)

    post program_path

    # The focus is not a label on the program — it picks the rep range every
    # lift will run, so the user has to be told which one and why.
    assert_match(/strength starting program because strength is specific to heavy loads/, flash[:notice])
    assert_match(/block now sets their rep ranges/, flash[:notice])
  end

  test "it does not claim to have started a block when one was already running" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: @user.local_date)
    @user.mesocycles.create!(focus: "power", started_on: @user.local_date - 3, weeks: 4)

    post program_path

    assert_no_match(/block now sets their rep ranges/, flash[:notice])
    assert_equal "power", @user.mesocycles.active.sole.focus, "an active block is never disturbed"
  end

  test "the targets page names the block that is setting the rep ranges" do
    @user.goal_periods.create!(goal_type: "increase_strength", started_on: @user.local_date)
    post program_path

    get exercise_prescriptions_path

    assert_response :success
    assert_select ".evidence-note", text: /strength block is setting reps, effort and baseline sets/
    assert_select ".evidence-note", text: /goes back to them when the block ends/
  end

  test "the targets page says nothing about a block when none is running" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: @user.local_date)
    post program_path
    @user.mesocycles.destroy_all

    get exercise_prescriptions_path

    assert_response :success
    assert_select ".evidence-note", { text: /is setting reps/, count: 0 }
  end
end
