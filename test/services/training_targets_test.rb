require "test_helper"

# Composing targets instead of applying them is what lets a block change
# recompose the plan. These tests pin the two halves of that: the block decides
# while it runs, and it decides nothing once it stops.
class TrainingTargetsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @today = @user.local_date
    @compound = Exercise.create!(user: @user, name: "Zzz Scheme Squat", modality: "barbell", is_compound: true)
    @isolation = Exercise.create!(user: @user, name: "Zzz Scheme Curl", modality: "dumbbell", is_compound: false)
  end

  test "a target keeps its own numbers when no block is running" do
    prescription = prescribe(@compound, rep_min: 8, rep_max: 12, working_sets: 4)

    targets = resolve(prescription)

    assert_equal 8, targets.rep_min
    assert_equal 12, targets.rep_max
    assert_equal 4, targets.working_sets
    assert_not targets.from_block?
  end

  test "an active block sets the scheme without the target being touched" do
    prescription = prescribe(@compound, rep_min: 8, rep_max: 12, working_sets: 4)
    start_block(focus: "strength")

    targets = resolve(prescription)

    assert_equal 3, targets.rep_min
    assert_equal 5, targets.rep_max
    assert_equal 4, targets.working_sets, "strength compounds run four sets"
    assert targets.from_block?
    assert_equal 12, prescription.reload.rep_max, "the stored target is the user's, not the block's"
  end

  test "compounds and isolations take different halves of the same scheme" do
    start_block(focus: "strength")

    assert_equal 3..5, range(resolve(prescribe(@compound)))
    assert_equal 6..8, range(resolve(prescribe(@isolation)))
  end

  test "a target that opts out keeps its own scheme inside the block" do
    prescription = prescribe(@compound, rep_min: 8, rep_max: 12, follows_block_scheme: false)
    start_block(focus: "power")

    targets = resolve(prescription)

    assert_equal 8..12, range(targets)
    assert_not targets.from_block?
  end

  test "the scheme leaves with the block" do
    prescription = prescribe(@compound, rep_min: 8, rep_max: 12)
    block = start_block(focus: "power")
    assert_equal 2..4, range(resolve(prescription))

    block.update!(ended_on: @today - 1)

    assert_equal 8..12, range(resolve(prescription))
  end

  test "targets are resolved against the block in force on the day asked about" do
    prescription = prescribe(@compound, rep_min: 8, rep_max: 12)
    @user.mesocycles.create!(focus: "strength", started_on: @today - 30, ended_on: @today - 10, weeks: 3)

    # A decision written about an old session has to see the old block.
    assert_equal 3..5, range(resolve(prescription, on: @today - 20))
    assert_equal 8..12, range(resolve(prescription, on: @today))
  end

  test "numbers arrive in one shape whichever side they came from" do
    start_block(focus: "hypertrophy")
    from_block = resolve(prescribe(@compound))
    from_target = resolve(prescribe(@isolation, follows_block_scheme: false))

    [ from_block, from_target ].each do |targets|
      assert_kind_of Integer, targets.rep_min
      assert_kind_of Integer, targets.working_sets
      assert_kind_of BigDecimal, targets.target_rir_min
    end
  end

  test "the label reads the way a lifter would say it" do
    start_block(focus: "hypertrophy")

    assert_equal "3 × 6–10 @ 1.0–2.0 RIR", resolve(prescribe(@compound)).label
  end

  private

  def resolve(prescription, on: @today)
    TrainingTargets.new(@user, on: on).targets_for(prescription)
  end

  def range(targets)
    targets.rep_min..targets.rep_max
  end

  def start_block(focus:)
    @user.mesocycles.create!(focus: focus, started_on: @today - 3, weeks: 4)
  end

  def prescribe(exercise, rep_min: 6, rep_max: 8, working_sets: 3, follows_block_scheme: true)
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: rep_min, rep_max: rep_max,
      target_rir_min: 1, target_rir_max: 2, increment_kg: 2.5,
      working_sets: working_sets, follows_block_scheme: follows_block_scheme,
      started_on: @today - 5
    )
  end
end
