require "test_helper"

class WorkoutSessionOrderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    # find_or_create_by!, because bin/ci leaves a seeded database behind and a
    # stray row from any other source makes create! fail on the second run.
    @bench = Exercise.find_or_create_by!(name: "Zzz Order Bench") { |e| e.modality = "barbell" }
    @squat = Exercise.find_or_create_by!(name: "Zzz Order Squat") { |e| e.modality = "barbell" }
    @session = @user.workout_sessions.create!(performed_at: Time.current)
  end

  # set_index restarts at 1 per exercise, so sorting the whole session by it
  # interleaves them — the ordinary two-lift session came back shuffled.
  test "sets are grouped by lift, in the order the lifts were first logged" do
    log(@bench, 1)
    log(@bench, 2)
    log(@squat, 1)
    log(@squat, 2)
    log(@bench, 3)

    assert_equal [ "Zzz Order Bench 1", "Zzz Order Bench 2", "Zzz Order Bench 3",
                   "Zzz Order Squat 1", "Zzz Order Squat 2" ], labelled(@session.reload)
  end

  test "a lift logged later stays after the one logged before it" do
    log(@squat, 1)
    log(@bench, 1)

    assert_equal [ "Zzz Order Squat 1", "Zzz Order Bench 1" ], labelled(@session.reload)
  end

  # Unsaved rows have no id to sort on, and building a session is exactly when
  # the logger asks for this order.
  test "unbuilt entries do not blow up the ordering" do
    log(@bench, 1)
    @session.set_entries.build(exercise: @squat, set_index: 1, weight_kg: 60, reps: 5, rir: 2)

    assert_equal 2, @session.ordered_set_entries.size
  end

  private

  def log(exercise, index)
    @session.set_entries.create!(exercise: exercise, set_index: index, weight_kg: 100, reps: 5, rir: 2)
  end

  def labelled(session)
    session.ordered_set_entries.map { |entry| "#{entry.exercise.name} #{entry.set_index}" }
  end
end
