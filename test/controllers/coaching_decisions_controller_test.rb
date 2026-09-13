require "test_helper"

# The audit page is the product's central claim made literal: any recommendation
# can be opened and read back to the evidence it came from. It renders untyped
# JSONB written by whichever rule produced the decision, so the tests care about
# shapes the renderer must survive as much as about the happy path.
class CoachingDecisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "shows a decision with its rule, conclusion and evidence" do
    decision = create_decision(
      inputs: { "metric_date" => "2026-03-01", "sleep_minutes" => 450 },
      output: { "status" => "push", "headline" => "Green light", "guidance" => "Train as planned." }
    )

    get coaching_decision_path(decision)

    assert_response :success
    assert_select "h1", "Green light"
    assert_select ".lift-stats", text: /daily_readiness\.v1/
    assert_select ".lift-stats", text: /Version 1\.0\.0/
    assert_select ".snapshot__row dt", text: "Metric date"
    assert_select ".snapshot__row dd", text: "Mar 1, 2026"
  end

  test "renders measurements in the reader's units rather than the stored ones" do
    decision = create_decision(
      decision_type: "double_progression",
      output: { "headline" => "Add load", "guidance" => "Earned.", "next_weight_kg" => 102.5 }
    )

    get coaching_decision_path(decision)
    assert_select ".snapshot__row dt", { text: "Next weight" }, "the unit belongs to the value, not the label"
    assert_select ".snapshot__row dd", text: /102\.5 kg/

    users(:one).update!(unit_system: "imperial")
    get coaching_decision_path(decision)

    assert_select ".snapshot__row dd", text: /225\.9738 lb/
  end

  test "renders a nested snapshot without flattening it" do
    decision = create_decision(
      decision_type: "double_progression",
      inputs: {
        "exercise_name" => "Zzz Audit Squat",
        "prescription" => { "id" => 4, "rep_min" => 6, "rep_max" => 8, "increment_kg" => 2.5 }
      }
    )

    get coaching_decision_path(decision)

    assert_response :success
    assert_select ".snapshot__row .snapshot", minimum: 1, text: /Rep min/
    assert_select ".snapshot__row dd", text: /2\.5 kg/
  end

  test "renders an array of objects as a list and an array of ids inline" do
    decision = create_decision(
      decision_type: "daily_nutrition",
      inputs: {
        "food_log_entry_ids" => [ 11, 12, 13 ],
        "sets" => [ { "reps" => 8, "weight_kg" => 100 }, { "reps" => 7, "weight_kg" => 100 } ]
      }
    )

    get coaching_decision_path(decision)

    assert_response :success
    assert_select ".snapshot__list > li", 2
    assert_select ".snapshot__row dd", text: /11, 12, 13/
  end

  test "survives an empty snapshot and a null value" do
    decision = create_decision(inputs: {}, output: { "headline" => "Nothing to say", "detail" => nil })

    get coaching_decision_path(decision)

    assert_response :success
    assert_select ".empty-state", text: /recorded no inputs/
    assert_select ".snapshot__row dd", text: "—"
  end

  test "resolves the ids in a snapshot back to what they point at" do
    exercise = Exercise.create!(name: "Zzz Audit Bench", modality: "barbell")
    session = @user.workout_sessions.create!(performed_at: 2.days.ago)
    decision = create_decision(
      decision_type: "double_progression",
      inputs: { "exercise_id" => exercise.id, "workout_session_id" => session.id }
    )

    get coaching_decision_path(decision)

    assert_response :success
    assert_select "a[href=?]", exercise_path(exercise), text: "Zzz Audit Bench"
    assert_select "a[href=?]", workout_session_path(session)
    assert_select ".snapshot__row dd", { text: exercise.id.to_s, count: 0 },
      "a bare foreign key is a JSON dump, not an audit trail"
  end

  test "falls back to the raw id when the record it pointed at is gone" do
    decision = create_decision(
      decision_type: "double_progression",
      inputs: { "workout_session_id" => 999_999 }
    )

    get coaching_decision_path(decision)

    assert_response :success
    # A deleted workout is exactly when a decision gets withdrawn, so this path matters.
    assert_select ".snapshot__row dd", text: "999999"
  end

  test "does not resolve another user's records through a snapshot" do
    theirs = users(:two).exercises.create!(name: "Zzz Audit Private", modality: "barbell")
    decision = create_decision(decision_type: "double_progression", inputs: { "exercise_id" => theirs.id })

    get coaching_decision_path(decision)

    assert_response :success
    assert_select "a", { text: "Zzz Audit Private", count: 0 }
    assert_select ".snapshot__row dd", text: theirs.id.to_s
  end

  test "shows the decisions it cites and the ones citing it" do
    parent = create_decision(decision_type: "daily_training", output: { "headline" => "Run the plan" })
    child = create_decision(output: { "headline" => "Green light" })
    parent.child_links.create!(child_decision: child, role: "readiness")

    get coaching_decision_path(parent)
    assert_select ".compact-list__item", text: /Daily readiness ##{child.id}/
    assert_select "a[href=?]", coaching_decision_path(child)

    get coaching_decision_path(child)
    assert_select ".compact-list__item", text: /Daily training plan ##{parent.id}/
    assert_select "a[href=?]", coaching_decision_path(parent)
  end

  test "a withdrawn decision says so and says why" do
    decision = create_decision(output: { "headline" => "Add 2.5 kg" })
    decision.retract!(reason: "workout_session_corrected")

    get coaching_decision_path(decision)

    assert_response :success
    assert_select ".withdrawn-note", text: /withdrawn on .* because the workout behind it was corrected/
  end

  test "a withdrawn child is marked where its parent cites it" do
    parent = create_decision(decision_type: "daily_training", output: { "headline" => "Run the plan" })
    child = create_decision(output: { "headline" => "Green light" })
    parent.child_links.create!(child_decision: child, role: "readiness")
    child.retract!(reason: "workout_session_deleted")

    get coaching_decision_path(parent)

    assert_select ".compact-list__item .pill", text: "Withdrawn"
  end

  test "another user's decision is not readable" do
    theirs = create_decision(user: users(:two))

    get coaching_decision_path(theirs)

    assert_response :not_found
  end

  test "signing out closes the audit trail" do
    decision = create_decision
    sign_out

    get coaching_decision_path(decision)

    assert_redirected_to new_session_path
  end

  test "a snapshot says where a number came from in words, not rule names" do
    decision = create_decision(
      decision_type: "double_progression",
      inputs: { "targets" => { "rep_max" => 5, "source" => "block_scheme" } }
    )

    get coaching_decision_path(decision)

    assert_response :success
    assert_select ".snapshot__row dd", text: /training block’s scheme/
  end

  private

  def create_decision(user: @user, decision_type: "daily_readiness", inputs: {}, output: nil)
    user.coaching_decisions.create!(
      decision_type: decision_type,
      rule_key: "#{decision_type}.v1",
      rule_version: "1.0.0",
      inputs: inputs,
      output: output || { "headline" => "Headline", "guidance" => "Guidance." },
      citations: [],
      confidence: "high"
    )
  end
end
