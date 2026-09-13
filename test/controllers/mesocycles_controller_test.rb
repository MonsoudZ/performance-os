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

  test "starting a block changes what the targets prescribe without rewriting them" do
    prescription = compound_target("Zzz Block Bench")

    post mesocycles_path, params: { mesocycle: { started_on: Date.current, weeks: 4, focus: "strength" } }

    get exercise_prescriptions_path
    assert_select ".prescription-card strong", text: /3–5/ # strength compound
    # The stored target is the user's own and the block never touches it, which
    # is what lets it come back when the block ends.
    assert_equal 12, prescription.reload.rep_max
  end

  test "ending a block gives every target its own rep range back" do
    prescription = compound_target("Zzz Block Row")
    block = @user.mesocycles.create!(started_on: Date.current - 5.days, weeks: 4, focus: "power")

    get exercise_prescriptions_path
    assert_select ".prescription-card strong", text: /2–4/ # power compound

    patch finish_mesocycle_path(block)

    get exercise_prescriptions_path
    assert_select ".prescription-card strong", text: /#{prescription.rep_min}–#{prescription.rep_max}/
  end

  test "the blocks page no longer offers to rewrite anything" do
    @user.mesocycles.create!(started_on: Date.current, weeks: 4, focus: "strength")

    get mesocycles_path

    assert_response :success
    assert_select "input[name='apply_scheme']", 0
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

  test "the focus select says what each focus will do to the rep ranges" do
    get mesocycles_path

    assert_response :success
    # Picking a focus used to only change the volume ramp; it now sets every
    # target's rep range, so the form has to say what each one means.
    assert_select ".focus-guide div", Mesocycle::FOCUSES.size
    assert_select ".focus-guide dd", text: /Compounds 3–5 reps/
    assert_select ".focus-guide dd", text: /Compounds 6–10 reps/
  end

  test "a suggested next block names the focus it is suggesting" do
    @user.mesocycles.create!(name: "Block 1", started_on: Date.current - 60.days, weeks: 6, focus: "power")

    get mesocycles_path

    assert_response :success
    assert_select ".evidence-note", text: /another power block of the same length/
  end
end
