require "test_helper"

class StrengthProgressionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @squat = Exercise.create!(name: "Squat", modality: "barbell")
  end

  test "tracks per-session best e1RM and detects PRs" do
    log(3.days.ago, weight: 100, reps: 5) # e1RM 116.7 (baseline)
    log(1.day.ago, weight: 100, reps: 8)  # e1RM 126.7 (PR)

    progress = StrengthProgression.new(@user).call.first

    assert_equal "Squat", progress.exercise.name
    assert_equal 2, progress.points.size
    assert_in_delta 126.7, progress.current_e1rm, 0.1
    assert_in_delta 126.7, progress.best_e1rm, 0.1
    assert_equal 1, progress.pr_count
    assert_not progress.points.first.pr
    assert progress.points.last.pr
  end

  test "uses the best working set in a session" do
    session = @user.workout_sessions.create!(performed_at: Time.current)
    session.set_entries.create!(exercise: @squat, set_index: 1, weight_kg: 90, reps: 10, rir: 1)  # e1RM 120
    session.set_entries.create!(exercise: @squat, set_index: 2, weight_kg: 110, reps: 3, rir: 1)   # e1RM 121
    session.set_entries.create!(exercise: @squat, set_index: 3, weight_kg: 140, reps: 1, rir: 1, is_warmup: true) # ignored

    progress = StrengthProgression.new(@user).call.first

    assert_in_delta 121.0, progress.current_e1rm, 0.1
  end

  test "does not count a regression as a PR" do
    log(3.days.ago, weight: 120, reps: 5) # baseline e1RM 140
    log(1.day.ago, weight: 100, reps: 5)  # e1RM 116.7, lower

    progress = StrengthProgression.new(@user).call.first

    assert_equal 0, progress.pr_count
    assert_in_delta 140.0, progress.best_e1rm, 0.1
  end

  private

  def log(performed_at, weight:, reps:)
    session = @user.workout_sessions.create!(performed_at: performed_at)
    session.set_entries.create!(exercise: @squat, set_index: 1, weight_kg: weight, reps: reps, rir: 1)
  end
end
