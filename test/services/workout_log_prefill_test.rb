require "test_helper"

class WorkoutLogPrefillTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Bench Press", modality: "barbell")
    @prescription = @user.exercise_prescriptions.create!(
      exercise: @exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      started_on: Date.current
    )
  end

  test "prefills prescribed sets from the latest progression target and prior actuals" do
    prior_workout = @user.workout_sessions.create!(performed_at: 1.day.ago)
    [ 8, 8, 7 ].each_with_index do |reps, index|
      prior_workout.set_entries.create!(
        exercise: @exercise,
        set_index: index + 1,
        weight_kg: 100,
        reps:,
        rir: 1
      )
    end
    CoachingDecision.create!(
      user: @user,
      decision_type: "double_progression",
      rule_key: DoubleProgressionEvaluator::RULE_KEY,
      rule_version: DoubleProgressionEvaluator::RULE_VERSION,
      inputs: {
        "exercise_id" => @exercise.id,
        "prescription" => { "id" => @prescription.id }
      },
      output: { "next_weight_kg" => 102.5 },
      citations: [],
      confidence: "high"
    )

    workout = @user.workout_sessions.new(performed_at: Time.current)
    contexts = WorkoutLogPrefill.new(@user, workout_session: workout, log_date: Date.current).call

    assert_equal 3, contexts.size
    assert_equal [ 102.5, 102.5, 102.5 ], contexts.map { |context| context.entry.weight_kg.to_f }
    # The load went up, so the reps reset to the bottom of the range. That is
    # what earning the increase costs; opening at the top would be asking the
    # user to correct the app on every row.
    assert_equal [ 6, 6, 6 ], contexts.map { |context| context.entry.reps }
    assert_equal [ 8, 8, 7 ], contexts.map { |context| context.last_set.reps }
  end

  # The common case: the load has not moved, so the guess is what you did last
  # time and a set you match needs no typing at all.
  test "repeating a load opens each row on what that set actually did" do
    prior = @user.workout_sessions.create!(performed_at: 1.day.ago)
    [ [ 7, 2 ], [ 7, 1 ], [ 6, 0 ] ].each_with_index do |(reps, rir), index|
      prior.set_entries.create!(exercise: @exercise, set_index: index + 1, weight_kg: 100, reps:, rir:)
    end

    workout = @user.workout_sessions.new(performed_at: Time.current)
    contexts = WorkoutLogPrefill.new(@user, workout_session: workout, log_date: Date.current).call

    assert_equal [ 100.0, 100.0, 100.0 ], contexts.map { |context| context.entry.weight_kg.to_f }
    assert_equal [ 7, 7, 6 ], contexts.map { |context| context.entry.reps }
    assert_equal [ 2.0, 1.0, 0.0 ], contexts.map { |context| context.entry.rir.to_f }
  end

  test "with nothing to go on the target stands" do
    workout = @user.workout_sessions.new(performed_at: Time.current)

    contexts = WorkoutLogPrefill.new(@user, workout_session: workout, log_date: Date.current).call

    assert contexts.any?
    assert contexts.all? { |context| context.last_set.nil? }
    assert_equal [ 8 ], contexts.map { |context| context.entry.reps }.uniq
  end

  # A fourth set planned against three done last time has no prior to copy, so
  # it falls back rather than blanking.
  test "a set beyond what was done last time falls back to the target" do
    prior = @user.workout_sessions.create!(performed_at: 1.day.ago)
    prior.set_entries.create!(exercise: @exercise, set_index: 1, weight_kg: 100, reps: 7, rir: 2)
    @prescription.update!(working_sets: 3)

    workout = @user.workout_sessions.new(performed_at: Time.current)
    contexts = WorkoutLogPrefill.new(@user, workout_session: workout, log_date: Date.current).call

    assert_equal [ 7, 8, 8 ], contexts.map { |context| context.entry.reps }
  end

  test "prefilled rows come from the block's scheme, not the stored target" do
    @exercise.update!(is_compound: true)
    @user.mesocycles.create!(focus: "strength", started_on: Date.current - 3, weeks: 4)
    session = @user.workout_sessions.new(performed_at: Time.current)

    contexts = WorkoutLogPrefill.new(@user, workout_session: session, log_date: Date.current).call

    # Strength compounds: four sets at 3-5 reps @ 2-3 RIR, against a target that
    # says three sets of 6-8 @ 1-2.
    assert_equal 4, contexts.size
    assert_equal [ 5 ], contexts.map { |context| context.entry.reps }.uniq
    assert_equal [ 2 ], contexts.map { |context| context.entry.rir.to_i }.uniq
    assert contexts.first.targets.from_block?
  end

  test "a target that opted out prefills its own rows inside a block" do
    @exercise.update!(is_compound: true)
    @prescription.update!(follows_block_scheme: false)
    @user.mesocycles.create!(focus: "strength", started_on: Date.current - 3, weeks: 4)
    session = @user.workout_sessions.new(performed_at: Time.current)

    contexts = WorkoutLogPrefill.new(@user, workout_session: session, log_date: Date.current).call

    assert_equal 3, contexts.size
    assert_equal [ 8 ], contexts.map { |context| context.entry.reps }.uniq
  end
end
