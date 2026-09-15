require "application_system_test_case"

# The workout logger is the one screen where the real behaviour lives in
# JavaScript: rows are added, duplicated, removed and renumbered client-side,
# and the volume readout is computed there. Nothing below can be asserted from a
# controller test, and a regression here silently loses logged sets.
class WorkoutLoggingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @squat = Exercise.create!(name: "Zzz System Squat", modality: "barbell")
    @bench = Exercise.create!(name: "Zzz System Bench", modality: "barbell")
    prescribe(@squat, working_sets: 3)
  end

  test "logs a workout from the prefilled rows" do
    sign_in @user
    visit new_workout_session_path

    assert_selector ".set-table__row", count: 3, wait: 5

    rows = all(".set-table__row")
    [ [ 100, 8 ], [ 100, 8 ], [ 100, 7 ] ].each_with_index do |(weight, reps), index|
      set_number rows[index].find("[data-workout-log-target='weight']"), weight
      set_number rows[index].find("[data-workout-log-target='reps']"), reps
      set_number rows[index].find("[data-workout-log-target='rir']"), 1
    end

    assert_difference -> { @user.workout_sessions.count }, 1 do
      click_on "Save and evaluate"
      assert_current_path(%r{/workout_sessions/\d+}, wait: 10)
    end

    assert_text "3 logged sets"

    session = @user.workout_sessions.order(:id).last

    assert_equal 3, session.set_entries.count
    assert_equal [ 100, 100, 100 ], session.set_entries.order(:set_index).map { |set| set.weight_kg.to_i }
    assert_equal [ 8, 8, 7 ], session.set_entries.order(:set_index).map(&:reps)
  end

  test "the live volume readout follows the inputs and ignores warm-ups" do
    sign_in @user
    visit new_workout_session_path

    rows = all(".set-table__row")
    set_number rows[0].find("[data-workout-log-target='weight']"), 100
    set_number rows[0].find("[data-workout-log-target='reps']"), 5

    assert_selector "[data-workout-log-target='volume']", text: "500 kg", wait: 5

    set_number rows[1].find("[data-workout-log-target='weight']"), 50
    set_number rows[1].find("[data-workout-log-target='reps']"), 4

    assert_selector "[data-workout-log-target='volume']", text: "700 kg"

    # Marking the second row a warm-up takes its 200 back out.
    rows[1].find("[data-workout-log-target='warmup']").click

    assert_selector "[data-workout-log-target='volume']", text: "500 kg"
  end

  test "duplicating a set copies its load and renumbers the rows" do
    sign_in @user
    visit new_workout_session_path

    first_row = all(".set-table__row").first
    set_number first_row.find("[data-workout-log-target='weight']"), 137.5
    set_number first_row.find("[data-workout-log-target='reps']"), 7
    set_number first_row.find("[data-workout-log-target='rir']"), 2

    first_row.find("button[aria-label='Add matching set']").click

    assert_selector ".set-table__row", count: 4

    added = all(".set-table__row").last

    assert_equal "137.5", added.find("[data-workout-log-target='weight']").value
    assert_equal "7", added.find("[data-workout-log-target='reps']").value
    assert_equal "2", added.find("[data-workout-log-target='rir']").value,
      "RIR is copied through a Stimulus target; an aria-label lookup here used to be the only thing holding it together"

    indexes = all("[data-workout-log-target='setIndex']").map(&:value)

    assert_equal %w[1 2 3 4], indexes, "set numbers are contiguous after an insert"
  end

  # The existing duplicate test prescribes one lift, so "the new row is last" is
  # true there whether or not it lands in the right place. With two lifts it is
  # not: a third bench set was going in below the squats and numbering itself 3,
  # which reads as a shuffle of a workout nobody performed that way.
  test "another set of a lift goes under that lift, not at the end of the session" do
    prescribe(@bench, working_sets: 2)
    sign_in @user
    visit new_workout_session_path

    assert_equal [ "Zzz System Bench 1", "Zzz System Bench 2",
                   "Zzz System Squat 1", "Zzz System Squat 2", "Zzz System Squat 3" ], logged_rows

    all(".set-table__row").first.find("button[aria-label='Add matching set']").click

    assert_equal [ "Zzz System Bench 1", "Zzz System Bench 2", "Zzz System Bench 3",
                   "Zzz System Squat 1", "Zzz System Squat 2", "Zzz System Squat 3" ], logged_rows

    # And a movement that is not in the session yet still joins at the end.
    all(".set-table__row").last.find("button[aria-label='Add matching set']").click

    assert_equal "Zzz System Squat 4", logged_rows.last
  end

  test "removing a set renumbers the remaining rows" do
    sign_in @user
    visit new_workout_session_path

    all(".set-table__row").first.find("button[aria-label='Remove set']").click

    assert_selector ".set-table__row", count: 2
    assert_equal %w[1 2], all("[data-workout-log-target='setIndex']").map(&:value)
  end

  test "adds an exercise from the catalog search" do
    sign_in @user
    visit new_workout_session_path

    find("[data-workout-log-target='search']").set("Zzz System Bench")

    assert_selector ".exercise-result", text: "Zzz System Bench", wait: 5
    find(".exercise-result", text: "Zzz System Bench").click

    assert_selector ".set-table__row", count: 4
    assert_selector ".set-table__row:last-of-type", text: "Zzz System Bench"

    added = all(".set-table__row").last
    set_number added.find("[data-workout-log-target='weight']"), 60
    set_number added.find("[data-workout-log-target='reps']"), 10
    set_number added.find("[data-workout-log-target='rir']"), 2

    click_on "Save and evaluate"
    assert_current_path(%r{/workout_sessions/\d+}, wait: 10)
    assert_text "4 logged sets"

    logged = @user.workout_sessions.order(:id).last.set_entries.map(&:exercise).uniq

    assert_includes logged, @bench, "the searched exercise reached the database"
  end

  test "an imperial user logs in pounds and the pounds are stored as kilograms" do
    @user.update!(unit_system: "imperial")
    sign_in @user
    visit new_workout_session_path

    assert_selector ".set-table__header span", text: /\Alb\z/i
    assert_no_selector ".set-table__header span", text: /\Akg\z/i

    row = all(".set-table__row").first
    set_number row.find("[data-workout-log-target='weight']"), 225
    set_number row.find("[data-workout-log-target='reps']"), 5

    assert_selector "[data-workout-log-target='volume']", text: "1,125 lb"

    click_on "Save and evaluate"
    assert_current_path(%r{/workout_sessions/\d+}, wait: 10)

    stored = @user.workout_sessions.order(:id).last.set_entries.order(:set_index).first

    assert_in_delta 102.058283, stored.weight_kg.to_f, 0.000001,
      "225 lb is stored as the exact kilogram equivalent"
  end

  test "the logger points at setting a target when none exists" do
    ExercisePrescription.delete_all
    sign_in @user
    visit new_workout_session_path

    assert_text "Set a training target before logging progression work"
    assert_no_selector ".set-table__row"
  end

  private

  def logged_rows
    all(".set-table__row").map do |row|
      "#{row[:'data-exercise-name']} #{row.find("[data-workout-log-target='setIndex']", visible: :all).value}"
    end
  end

  def prescribe(exercise, working_sets: 3)
    @user.exercise_prescriptions.create!(
      exercise: exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: working_sets,
      started_on: Date.current
    )
  end
end
