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
end
