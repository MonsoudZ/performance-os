require "test_helper"

class MesocyclesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "renders the blocks page" do
    get mesocycles_path

    assert_response :success
    assert_select "h1", "Training blocks."
  end

  test "starts a block and enqueues a plan recompute" do
    assert_difference "Mesocycle.count", 1 do
      assert_enqueued_with(job: TrainingPlanRecomputeJob) do
        post mesocycles_path, params: { mesocycle: { name: "Block 1", started_on: Date.current, weeks: 4, deload_week: 4 } }
      end
    end

    assert_redirected_to mesocycles_path
  end

  test "starts a block with a chosen focus" do
    post mesocycles_path, params: { mesocycle: { started_on: Date.current, weeks: 4, focus: "strength" } }

    assert_equal "strength", @user.mesocycles.order(:id).last.focus
  end

  test "starting a block with the scheme checkbox rewrites the targets" do
    prescription = compound_target("Bench")

    post mesocycles_path, params: {
      apply_scheme: "1", mesocycle: { started_on: Date.current, weeks: 4, focus: "strength" }
    }

    assert_equal 5, prescription.reload.rep_max # strength compound 3-5
  end

  test "applies a scheme to targets from the active block" do
    prescription = compound_target("Overhead Press")
    block = @user.mesocycles.create!(started_on: Date.current, weeks: 4, focus: "power")

    patch apply_scheme_mesocycle_path(block)

    assert_equal 4, prescription.reload.rep_max # power compound 2-4
    assert_redirected_to exercise_prescriptions_path
  end

  test "starting a new block retires the active one" do
    old = @user.mesocycles.create!(started_on: Date.current - 10.days, weeks: 4)

    post mesocycles_path, params: { mesocycle: { started_on: Date.current, weeks: 6 } }

    assert_equal Date.current - 1.day, old.reload.ended_on
    assert_equal 1, @user.mesocycles.active.count
  end

  test "ends a block" do
    block = @user.mesocycles.create!(started_on: Date.current - 5.days, weeks: 4)

    patch finish_mesocycle_path(block)

    assert_equal Date.current - 1.day, block.reload.ended_on
    assert_redirected_to mesocycles_path
  end

  test "rejects a deload week beyond the block length" do
    assert_no_difference "Mesocycle.count" do
      post mesocycles_path, params: { mesocycle: { started_on: Date.current, weeks: 4, deload_week: 6 } }
    end

    assert_response :unprocessable_entity
  end

  test "pre-fills the form with a suggested next block when none is active" do
    @user.mesocycles.create!(name: "Block 1", started_on: Date.current - 60.days, weeks: 6, deload_week: 6)

    get mesocycles_path

    assert_response :success
    assert_select "input[name='mesocycle[name]'][value='Block 2']"
    assert_select "input[name='mesocycle[weeks]'][value='6']"
  end

  test "cannot end another user's block" do
    foreign = users(:two).mesocycles.create!(started_on: Date.current, weeks: 4)

    patch finish_mesocycle_path(foreign)

    assert_response :not_found
  end

  private

  def compound_target(name)
    exercise = Exercise.create!(user: @user, name: name, modality: "barbell", is_compound: true)
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 8, rep_max: 12, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current
    )
  end
end
