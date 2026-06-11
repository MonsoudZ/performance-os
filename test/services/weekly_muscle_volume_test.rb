require "test_helper"

class WeeklyMuscleVolumeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @bench = Exercise.create!(name: "Bench", modality: "barbell")
    chest = MuscleGroup.create!(name: "chest")
    triceps = MuscleGroup.create!(name: "triceps")
    @bench.exercise_muscle_contributions.create!(muscle_group: chest, role: "primary", fraction: 1.0)
    @bench.exercise_muscle_contributions.create!(muscle_group: triceps, role: "secondary", fraction: 0.5)
  end

  test "sums fractional sets per muscle for the week" do
    workout = @user.workout_sessions.create!(performed_at: Time.current)
    3.times { |i| working_set(workout, i + 1) }

    result = WeeklyMuscleVolume.new(@user).call

    assert_equal 3.0, entry(result, "chest").fractional_sets
    assert_equal 1.5, entry(result, "triceps").fractional_sets
  end

  test "ignores warm-up sets, blank sets, and other weeks" do
    this_week = @user.workout_sessions.create!(performed_at: Time.current)
    working_set(this_week, 1)
    this_week.set_entries.create!(exercise: @bench, set_index: 2, weight_kg: 60, reps: 10, rir: 4, is_warmup: true)
    this_week.set_entries.create!(exercise: @bench, set_index: 3, weight_kg: nil, reps: nil, rir: nil)

    last_week = @user.workout_sessions.create!(performed_at: 8.days.ago)
    working_set(last_week, 1)

    result = WeeklyMuscleVolume.new(@user).call

    # Only the single working set this week counts.
    assert_equal 1.0, entry(result, "chest").fractional_sets
  end

  test "flags volume against the muscle landmark" do
    workout = @user.workout_sessions.create!(performed_at: Time.current)
    3.times { |i| working_set(workout, i + 1) }

    chest = entry(WeeklyMuscleVolume.new(@user).call, "chest")
    assert_equal "under", chest.status # 3 sets < chest MEV of 8
    assert_equal({ mev: 8, mav: 16, mrv: 22 }, chest.landmark)
  end

  private

  def working_set(workout, index)
    workout.set_entries.create!(exercise: @bench, set_index: index, weight_kg: 100, reps: 8, rir: 1)
  end

  def entry(result, muscle)
    result.find { |item| item.muscle == muscle }
  end
end
