require "test_helper"

class ExercisePrescriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Zzz Rx Squat", modality: "barbell")
  end

  test "a valid target needs a coherent rep and RIR range" do
    assert build.valid?
    assert_not build(rep_min: 8, rep_max: 6).valid?, "rep_max below rep_min"
    assert_not build(target_rir_min: 3, target_rir_max: 1).valid?, "RIR max below min"
    assert_not build(rep_min: 0).valid?
    assert_not build(working_sets: 0).valid?
    assert_not build(increment_kg: 0).valid?
  end

  test "the progression model is limited to the two the engine implements" do
    assert build(progression_model: "double_progression").valid?
    assert build(progression_model: "top_set").valid?
    assert_not build(progression_model: "wave_loading").valid?
  end

  test "top_set? reflects which set gates the increase" do
    assert_predicate build(progression_model: "top_set"), :top_set?
    assert_not build(progression_model: "double_progression").top_set?
  end

  test "target_label reads the way a lifter would say it" do
    prescription = build(working_sets: 3, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2)

    assert_equal "3 × 6–8 @ 1.0–2.0 RIR", prescription.target_label
  end

  test "a target cannot name an exercise belonging to another user" do
    theirs = users(:two).exercises.create!(name: "Zzz Private Lift", modality: "barbell")

    assert_not build(exercise: theirs).valid?
  end

  test "a shared catalog exercise is available to anyone" do
    assert build(exercise: Exercise.create!(name: "Zzz Catalog Lift", modality: "barbell")).valid?
  end

  test "only one target per exercise can be active at a time" do
    create

    assert_raises(ActiveRecord::RecordNotUnique) do
      # Bypasses validation to prove the database itself holds the invariant.
      @user.exercise_prescriptions.insert_all!([ {
        exercise_id: @exercise.id, rep_min: 6, rep_max: 8,
        target_rir_min: 1, target_rir_max: 2, increment_kg: 2.5,
        working_sets: 3, started_on: Date.current, ended_on: nil,
        progression_model: "double_progression",
        created_at: Time.current, updated_at: Time.current
      } ])
    end
  end

  test "a retired target frees the slot for a new one" do
    first = create(started_on: 30.days.ago.to_date)
    first.update!(ended_on: 1.day.ago.to_date)

    assert create(started_on: Date.current).persisted?
  end

  test "active_on covers the whole inclusive span" do
    prescription = create(started_on: Date.new(2026, 3, 1), ended_on: Date.new(2026, 3, 10))
    scope = @user.exercise_prescriptions

    assert_includes scope.active_on(Date.new(2026, 3, 1)), prescription, "the start date counts"
    assert_includes scope.active_on(Date.new(2026, 3, 10)), prescription, "the end date counts"
    assert_not_includes scope.active_on(Date.new(2026, 2, 28)), prescription
    assert_not_includes scope.active_on(Date.new(2026, 3, 11)), prescription
  end

  test "an open-ended target stays active indefinitely" do
    prescription = create(started_on: Date.new(2026, 1, 1))

    assert_includes @user.exercise_prescriptions.active_on(Date.new(2030, 1, 1)), prescription
  end

  test "ended_on cannot precede started_on" do
    assert_not build(started_on: Date.current, ended_on: 1.day.ago.to_date).valid?
  end

  private

  def build(**attributes)
    @user.exercise_prescriptions.build({
      exercise: @exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      started_on: Date.current
    }.merge(attributes))
  end

  def create(**attributes)
    build(**attributes).tap(&:save!)
  end
end
