require "test_helper"

class SetEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Zzz Set Squat", modality: "barbell")
    @session = @user.workout_sessions.create!(performed_at: Time.current)
  end

  test "a set records reps, load and effort within sane bounds" do
    assert build.valid?
    assert_not build(set_index: 0).valid?
    assert_not build(reps: 0).valid?
    assert_not build(weight_kg: -1).valid?
    assert_not build(rir: -1).valid?
    assert_not build(rpe: 11).valid?
  end

  test "load, reps and effort may be blank — a set can be logged before it is finished" do
    assert build(weight_kg: nil, reps: nil, rir: nil, rpe: nil).valid?
  end

  test "set numbers are unique within a session for one exercise" do
    create(set_index: 1)

    assert_raises(ActiveRecord::RecordNotUnique) do
      @session.set_entries.insert_all!([ {
        exercise_id: @exercise.id, set_index: 1, weight_kg: 60, reps: 5,
        is_warmup: false, created_at: Time.current, updated_at: Time.current
      } ])
    end
  end

  test "two exercises can both have a set one in the same session" do
    other = Exercise.create!(name: "Zzz Set Bench", modality: "barbell")
    create(set_index: 1)

    assert @session.set_entries.create!(exercise: other, set_index: 1, weight_kg: 60, reps: 5).persisted?
  end

  test "a set cannot name an exercise belonging to another user" do
    theirs = users(:two).exercises.create!(name: "Zzz Set Private", modality: "barbell")

    assert_not build(exercise: theirs).valid?
  end

  # estimated_1rm_kg is a stored generated column (Epley), so it is computed by
  # the database and cannot be assigned. Its scale was widened alongside
  # weight_kg; if the two ever drift apart the estimate is silently truncated.
  test "the estimated 1RM is computed by the database from load and reps" do
    set = create(weight_kg: 100, reps: 5)

    assert_in_delta 116.666667, set.reload.estimated_1rm_kg.to_f, 0.000001
  end

  test "the estimated 1RM keeps the precision of the load it came from" do
    set = create(weight_kg: Units.weight_to_kg(225, "imperial"), reps: 8)

    # 102.058283 kg at 8 reps: the estimate must not be rounded to two places.
    assert_in_delta 129.273825, set.reload.estimated_1rm_kg.to_f, 0.000001
  end

  test "a single rep estimates as the load itself" do
    set = create(weight_kg: 140, reps: 1)

    assert_in_delta 144.666667, set.reload.estimated_1rm_kg.to_f, 0.000001
  end

  test "a set with no load has no estimate" do
    assert_nil create(weight_kg: nil, reps: 5).reload.estimated_1rm_kg
    assert_nil create(set_index: 2, weight_kg: 100, reps: nil).reload.estimated_1rm_kg
  end

  test "deleting a session takes its sets" do
    create

    assert_difference -> { SetEntry.count }, -1 do
      @session.destroy
    end
  end

  test "an exercise with logged sets cannot be deleted" do
    create

    assert_not @exercise.destroy
    assert_includes @exercise.errors.attribute_names, :base
  end

  private

  def build(**attributes)
    @session.set_entries.build({
      exercise: @exercise,
      set_index: 1,
      weight_kg: 100,
      reps: 8,
      rir: 1
    }.merge(attributes))
  end

  def create(**attributes)
    build(**attributes).tap(&:save!)
  end
end
