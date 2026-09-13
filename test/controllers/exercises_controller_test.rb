require "test_helper"

class ExercisesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "lists catalog and custom exercises but not another user's" do
    Exercise.create!(name: "Zzz Shared Lift", modality: "barbell")
    Current.user.exercises.create!(name: "Zzz Custom Lift", modality: "other")
    users(:two).exercises.create!(name: "Zzz Private Lift", modality: "barbell")

    get exercises_path

    assert_response :success
    assert_select "h1", "Exercise library."
    assert_select ".library-card h2", text: "Zzz Shared Lift"
    assert_select ".library-card h2", text: "Zzz Custom Lift"
    assert_select ".library-card h2", text: "Zzz Private Lift", count: 0
  end

  test "filters the library by name" do
    Exercise.create!(name: "Zzz Zebra Lift", modality: "barbell")
    Exercise.create!(name: "Zzz Yak Lift", modality: "barbell")

    get exercises_path, params: { q: "zebra" }

    assert_select ".library-card h2", 1
    assert_select ".library-card h2", text: "Zzz Zebra Lift"
  end

  test "filters the library by modality" do
    Exercise.create!(name: "Zzz Machine Lift", modality: "machine")
    Exercise.create!(name: "Zzz Barbell Lift", modality: "barbell")

    get exercises_path, params: { modality: "machine", q: "Zzz" }

    assert_select ".library-card h2", 1
    assert_select ".library-card h2", text: "Zzz Machine Lift"
  end

  test "ignores an unknown modality filter rather than returning nothing" do
    Exercise.create!(name: "Zzz Shared Lift", modality: "barbell")

    get exercises_path, params: { modality: "telekinesis", q: "Zzz" }

    assert_response :success
    assert_select ".library-card h2", text: "Zzz Shared Lift"
  end

  test "marks exercises that have an active training target" do
    row = Exercise.create!(name: "Zzz Targeted Lift", modality: "barbell")
    Exercise.create!(name: "Zzz Untargeted Lift", modality: "machine")
    prescribe(row)

    get exercises_path, params: { q: "Zzz" }

    assert_select ".library-card", text: /Zzz Targeted Lift/ do
      assert_select ".pill--active", text: "Active target"
    end
    assert_select ".pill--active", 1
  end

  test "shows an exercise with its target, history, and decision trail" do
    squat = Exercise.create!(name: "Zzz Audited Squat", modality: "barbell")
    prescribe(squat)
    session = @user.workout_sessions.create!(performed_at: 1.day.ago)
    session.set_entries.create!(exercise: squat, set_index: 1, weight_kg: 100, reps: 8, rir: 1)
    CoachingDecision.create!(
      user: @user,
      decision_type: "double_progression",
      rule_key: DoubleProgressionEvaluator::RULE_KEY,
      rule_version: DoubleProgressionEvaluator::RULE_VERSION,
      inputs: { "exercise_id" => squat.id },
      output: {
        "status" => "increase",
        "headline" => "Add 2.5 kg next time",
        "guidance" => "You hit the top of the rep range.",
        "current_weight_kg" => 100.0,
        "next_weight_kg" => 102.5
      },
      citations: [],
      confidence: "high"
    )

    get exercise_path(squat)

    assert_response :success
    assert_select "h1", "Zzz Audited Squat"
    assert_select "h2", text: "3 × 6–8 @ 1.0–2.0 RIR"
    assert_select ".decision-trail__item--increase", 1
    assert_select ".decision-trail__head strong", text: "Add 2.5 kg next time"
    assert_select ".decision-trail__item .pill", text: "Load increased"
    assert_select ".decision-trail__meta", text: /100 → 102.5 kg/
    assert_select ".appearance__set", text: /100 kg × 8/
  end

  test "shows empty states for an exercise with no target and no history" do
    squat = Exercise.create!(name: "Zzz Audited Squat", modality: "barbell")

    get exercise_path(squat)

    assert_response :success
    assert_select "h2", text: "No active target"
    assert_select ".empty-state", minimum: 2
    assert_select ".decision-trail__item", 0
  end

  test "labels a retracted decision in the trail" do
    squat = Exercise.create!(name: "Zzz Audited Squat", modality: "barbell")
    CoachingDecision.create!(
      user: @user,
      decision_type: "double_progression",
      rule_key: DoubleProgressionEvaluator::RULE_KEY,
      rule_version: DoubleProgressionEvaluator::RULE_VERSION,
      inputs: { "exercise_id" => squat.id },
      output: { "status" => "increase", "headline" => "Add 2.5 kg", "guidance" => "Earned." },
      citations: [],
      confidence: "high"
    ).retract!(reason: "workout_deleted")

    get exercise_path(squat)

    assert_response :success
    assert_select ".decision-trail__item.is-retracted", 1
    assert_select ".decision-trail__retracted", text: /Workout deleted/
  end

  test "does not show another user's exercise" do
    theirs = users(:two).exercises.create!(name: "Zzz Private Lift", modality: "barbell")

    get exercise_path(theirs)

    assert_response :not_found
  end

  test "renders the new custom exercise form" do
    get new_exercise_path

    assert_response :success
    assert_select "h1", "Add a custom exercise."
  end

  test "creates a user-owned exercise" do
    assert_difference "Exercise.count", 1 do
      post exercises_path, params: {
        exercise: { name: "Spanish Squat", modality: "machine", default_unit: "kg", is_compound: true }
      }
    end

    exercise = Exercise.order(:id).last
    assert_equal @user, exercise.user
    assert_equal "Spanish Squat", exercise.name
    assert exercise.is_compound
    assert_redirected_to new_exercise_prescription_path
  end

  test "rejects an invalid modality" do
    assert_no_difference "Exercise.count" do
      post exercises_path, params: {
        exercise: { name: "Mystery Lift", modality: "telekinesis", default_unit: "kg" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    sign_out
    squat = Exercise.create!(name: "Zzz Audited Squat", modality: "barbell")

    get exercises_path
    assert_redirected_to new_session_path

    get exercise_path(squat)
    assert_redirected_to new_session_path
  end

  test "the new exercise becomes available to prescribe" do
    post exercises_path, params: {
      exercise: { name: "Hatfield Squat", modality: "barbell", default_unit: "kg" }
    }

    assert_includes Exercise.available_to(@user).pluck(:name), "Hatfield Squat"
  end

  private

  def prescribe(exercise)
    @user.exercise_prescriptions.create!(
      exercise: exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      started_on: Date.current
    )
  end
end
