require "test_helper"

class ExerciseHistoryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @squat = Exercise.create!(name: "Squat", modality: "barbell")
    @bench = Exercise.create!(name: "Bench", modality: "barbell")
  end

  test "groups this exercise's sets by session, newest first" do
    older = log_session(3.days.ago, [ [ 100, 8 ], [ 100, 7 ] ])
    newer = log_session(1.day.ago, [ [ 102.5, 8 ] ])
    log_session(2.days.ago, [ [ 60, 10 ] ], exercise: @bench)

    appearances = history.appearances

    assert_equal [ newer.id, older.id ], appearances.map { |a| a.workout_session.id }
    assert_equal 2, appearances.last.sets.size
  end

  test "summarizes volume and the top set from working sets only" do
    session = @user.workout_sessions.create!(performed_at: Time.current)
    session.set_entries.create!(exercise: @squat, set_index: 1, weight_kg: 60, reps: 5, rir: 4, is_warmup: true)
    session.set_entries.create!(exercise: @squat, set_index: 2, weight_kg: 100, reps: 8, rir: 1)
    session.set_entries.create!(exercise: @squat, set_index: 3, weight_kg: 110, reps: 5, rir: 1)

    appearance = history.appearances.first

    assert_equal 3, appearance.sets.size, "the log keeps warm-ups"
    assert_equal 2, appearance.working_sets.size
    assert_equal 1350, appearance.volume_kg, "warm-up load is excluded"
    assert_equal 110.0, appearance.top_set.weight_kg.to_f
  end

  test "counts sessions and working sets across the whole history" do
    log_session(2.days.ago, [ [ 100, 8 ], [ 100, 8 ] ])
    log_session(1.day.ago, [ [ 100, 8 ] ])
    log_session(1.day.ago, [ [ 60, 10 ] ], exercise: @bench)

    assert_equal 2, history.session_count
    assert_equal 3, history.total_working_sets
    assert_equal 100.0, history.heaviest_set.weight_kg.to_f
  end

  test "exposes the active target and the retired ones behind it" do
    retired = prescription(started_on: 30.days.ago.to_date, ended_on: 8.days.ago.to_date)
    active = prescription(started_on: 7.days.ago.to_date)
    prescription(started_on: 7.days.ago.to_date, exercise: @bench)

    assert_equal active, history.active_prescription
    assert_equal [ retired ], history.past_prescriptions
  end

  test "has no active target when every target is retired" do
    prescription(started_on: 30.days.ago.to_date, ended_on: 8.days.ago.to_date)

    assert_nil history.active_prescription
    assert_equal 1, history.past_prescriptions.size
  end

  test "lists progression decisions for this exercise only, newest first" do
    old = decision(created_at: 3.days.ago, status: "hold")
    recent = decision(created_at: 1.day.ago, status: "increase")
    decision(created_at: 1.day.ago, status: "increase", exercise: @bench)

    assert_equal [ recent.id, old.id ], history.progression_decisions.map(&:id)
  end

  test "keeps retracted decisions in the trail" do
    kept = decision(created_at: 2.days.ago, status: "increase")
    retracted = decision(created_at: 1.day.ago, status: "increase")
    retracted.retract!(reason: "workout_deleted")

    assert_equal [ retracted.id, kept.id ], history.progression_decisions.map(&:id)
    assert history.progression_decisions.first.retracted_at?
  end

  test "reports an empty history for an exercise that was never logged" do
    assert_not history.ever_logged?
    assert_empty history.appearances
    assert_nil history.last_performed_on
    assert_nil history.heaviest_set
    assert_equal 0, history.session_count
    assert_equal 0, history.total_working_sets
  end

  test "caps the session list at the requested limit" do
    5.times { |index| log_session((index + 1).days.ago, [ [ 100, 5 ] ]) }

    assert_equal 2, ExerciseHistory.new(@user, @squat, session_limit: 2).appearances.size
    assert_equal 5, history.session_count, "the limit is display-only, not a count"
  end

  test "ignores another user's sessions and decisions" do
    other = users(:two)
    other_session = other.workout_sessions.create!(performed_at: 1.day.ago)
    other_session.set_entries.create!(exercise: @squat, set_index: 1, weight_kg: 200, reps: 5, rir: 1)
    CoachingDecision.create!(
      user: other,
      decision_type: "double_progression",
      rule_key: DoubleProgressionEvaluator::RULE_KEY,
      rule_version: DoubleProgressionEvaluator::RULE_VERSION,
      inputs: { "exercise_id" => @squat.id },
      output: { "status" => "increase" },
      citations: [],
      confidence: "high"
    )

    assert_not history.ever_logged?
    assert_empty history.progression_decisions
  end

  private

  def history
    ExerciseHistory.new(@user, @squat)
  end

  def log_session(performed_at, sets, exercise: @squat)
    session = @user.workout_sessions.create!(performed_at: performed_at)
    sets.each_with_index do |(weight, reps), index|
      session.set_entries.create!(exercise: exercise, set_index: index + 1, weight_kg: weight, reps: reps, rir: 1)
    end
    session
  end

  def prescription(started_on:, ended_on: nil, exercise: @squat)
    @user.exercise_prescriptions.create!(
      exercise: exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      started_on: started_on,
      ended_on: ended_on
    )
  end

  def decision(created_at:, status:, exercise: @squat)
    CoachingDecision.create!(
      user: @user,
      decision_type: "double_progression",
      rule_key: DoubleProgressionEvaluator::RULE_KEY,
      rule_version: DoubleProgressionEvaluator::RULE_VERSION,
      inputs: { "exercise_id" => exercise.id, "exercise_name" => exercise.name },
      output: { "status" => status, "headline" => "Headline", "guidance" => "Guidance" },
      citations: [],
      confidence: "high",
      created_at: created_at
    )
  end
end
