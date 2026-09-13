require "test_helper"

# DateRanged is what keeps a user's history readable: editing a goal, a block or
# a training target opens a new record rather than mutating the old one, so a
# decision made last month still points at the target that was live then. The
# arithmetic is small and easy to get subtly wrong at the boundaries, and it is
# shared by three models.
class DateRangedTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "ended_on_for retires a record the day before its successor opens" do
    goal = create_goal(started_on: Date.new(2026, 1, 1))

    assert_equal Date.new(2026, 2, 9), goal.ended_on_for(Date.new(2026, 2, 10))
  end

  test "a record opened and replaced on the same day keeps a one-day span" do
    goal = create_goal(started_on: Date.new(2026, 3, 5))

    assert_equal Date.new(2026, 3, 5), goal.ended_on_for(Date.new(2026, 3, 5)),
      "clamping to the start date keeps the range valid instead of inverting it"
    assert_equal Date.new(2026, 3, 5), goal.ended_on_for(Date.new(2026, 3, 1)),
      "a pivot before the start cannot push the end earlier than the start"
  end

  test "the active scope is the records that have not ended" do
    open_goal = create_goal(started_on: 10.days.ago.to_date)
    open_goal.update!(ended_on: 2.days.ago.to_date)
    current = create_goal(started_on: 1.day.ago.to_date)

    assert_equal [ current ], @user.goal_periods.active.to_a
  end

  test "every including model rejects an end before its start" do
    exercise = Exercise.create!(name: "Zzz Ranged Lift", modality: "barbell")

    invalid = [
      @user.goal_periods.build(goal_type: "build_muscle", started_on: Date.current, ended_on: 1.day.ago.to_date),
      @user.mesocycles.build(started_on: Date.current, ended_on: 1.day.ago.to_date, weeks: 4),
      @user.exercise_prescriptions.build(
        exercise: exercise, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
        increment_kg: 2.5, working_sets: 3, started_on: Date.current, ended_on: 1.day.ago.to_date
      )
    ]

    invalid.each do |record|
      assert_not record.valid?, "#{record.class} allowed an end before its start"
      assert_includes record.errors.attribute_names, :ended_on
    end
  end

  test "started_on is required by every including model" do
    assert_not @user.goal_periods.build(goal_type: "build_muscle").valid?
    assert_not @user.mesocycles.build(weeks: 4).valid?
  end

  test "only one goal period can be open at a time" do
    create_goal(started_on: 10.days.ago.to_date)

    assert_raises(ActiveRecord::RecordNotUnique) do
      @user.goal_periods.insert_all!([ {
        goal_type: "lose_fat", started_on: Date.current, ended_on: nil, params: {},
        created_at: Time.current, updated_at: Time.current
      } ])
    end
  end

  test "superseding a goal leaves exactly one open and a readable history" do
    first = create_goal(started_on: Date.new(2026, 1, 1), goal_type: "build_muscle")
    first.update!(ended_on: first.ended_on_for(Date.new(2026, 2, 1)))
    second = create_goal(started_on: Date.new(2026, 2, 1), goal_type: "lose_fat")

    assert_equal [ second ], @user.goal_periods.active.to_a
    assert_equal Date.new(2026, 1, 31), first.reload.ended_on
    assert_equal [ first ], @user.goal_periods.active_on(Date.new(2026, 1, 15)).to_a
    assert_equal [ second ], @user.goal_periods.active_on(Date.new(2026, 2, 15)).to_a
    assert_empty @user.goal_periods.active_on(Date.new(2025, 12, 31)),
      "no goal was live before the first one opened"
  end

  private

  def create_goal(started_on:, goal_type: "build_muscle")
    @user.goal_periods.create!(goal_type: goal_type, started_on: started_on)
  end
end
