require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "shows the check-in form with hours-based sleep on a fresh day" do
    get root_path

    assert_response :success
    assert_select "form.check-in__form"
    assert_select "select[name='daily_readiness_input[sleep_hours]']"
    assert_select "select[name='daily_readiness_input[sleep_hours]'] option[selected][value='7.5']"
  end

  test "a watch-only sync is not checked in and auto-fills sleep and heart metrics" do
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date,
      sleep_minutes: 450, hrv_sdnn_ms: 52, resting_hr: 55,
      source: "healthkit"
    )

    get root_path

    assert_response :success
    # Still prompts for the subjective taps...
    assert_select "form.check-in__form"
    # ...but sleep is shown as synced rather than a manual field, and the watch
    # metrics are noted.
    assert_select ".synced-field"
    assert_select "select[name='daily_readiness_input[sleep_hours]']", count: 0
    assert_select ".synced-note"
  end

  test "the check-in actually generates a plan the dashboard then renders" do
    perform_enqueued_jobs do
      post readiness_check_in_path, params: {
        daily_readiness_input: { sleep_hours: 7.5, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
      }
    end

    # The background job wrote a real readiness score and daily_training plan...
    assert @user.readiness_scores.find_by(score_date: @user.local_date), "expected a generated readiness score"
    decision = @user.coaching_decisions.where(decision_type: "daily_training").order(:created_at).last
    assert decision, "expected a generated daily_training plan"

    # ...and the dashboard renders that plan, not the "Calculating…" placeholder.
    get root_path

    assert_response :success
    assert_select ".score-card--empty", count: 0
    assert_select ".score-card h2", text: decision.output["headline"]
  end

  test "nudges to start the next block when one recently ended" do
    @user.mesocycles.create!(name: "Block 1", started_on: Date.current - 30.days, ended_on: Date.current - 2.days, weeks: 4)

    get root_path

    assert_response :success
    assert_select ".block-nudge"
  end

  test "shows complete once the subjective taps are in" do
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date,
      sleep_minutes: 450, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3,
      source: "manual"
    )

    get root_path

    assert_response :success
    assert_select ".completed h3", "Today’s check-in is complete."
    assert_select "form.check-in__form", count: 0
  end

  test "offers the AI coach panel with prior exchanges when configured and a plan exists" do
    original_key = Rails.application.config.x.anthropic[:api_key]
    Rails.application.config.x.anthropic[:api_key] = "test-key"
    decision = @user.coaching_decisions.create!(
      decision_type: "daily_training", rule_key: "daily_training_orchestrator.v1", rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "status" => "push", "headline" => "Run the plan", "guidance" => "Go.", "lifts" => [] },
      confidence: "high"
    )
    @user.coach_narratives.create!(
      question: "Why push today?", coaching_decision: decision,
      status: "complete", answer: "Because your readiness is high.", model_id: "claude-opus-4-8"
    )

    get root_path

    assert_response :success
    assert_select "section.coach"
    assert_select ".coach__question", text: "Why push today?"
    assert_select ".coach__answer", text: /readiness is high/
  ensure
    Rails.application.config.x.anthropic[:api_key] = original_key
  end

  test "hides the AI coach panel when no API key is configured" do
    original_key = Rails.application.config.x.anthropic[:api_key]
    Rails.application.config.x.anthropic[:api_key] = nil
    @user.coaching_decisions.create!(
      decision_type: "daily_training", rule_key: "daily_training_orchestrator.v1", rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "status" => "push", "headline" => "Run the plan", "guidance" => "Go.", "lifts" => [] },
      confidence: "high"
    )

    get root_path

    assert_response :success
    assert_select "section.coach", count: 0
  ensure
    Rails.application.config.x.anthropic[:api_key] = original_key
  end
  test "the dashboard says when an earlier version of today's plan was withdrawn" do
    withdrawn = daily_training_decision
    withdrawn.retract!(reason: "workout_session_corrected")
    daily_training_decision

    get root_path

    assert_response :success
    assert_select ".withdrawn-note", { count: 1 },
      "a plan that changed under the user has to say so"
    assert_select ".withdrawn-note", text: /earlier version of today's plan was withdrawn/
    assert_select ".withdrawn-note", text: /the workout behind it was corrected/
  end

  test "the dashboard stays quiet when nothing was withdrawn" do
    daily_training_decision

    get root_path

    assert_response :success
    assert_select ".withdrawn-note", 0
  end

  test "a withdrawn plan is never shown as the current one" do
    withdrawn = daily_training_decision(headline: "Withdrawn headline")
    withdrawn.retract!(reason: "workout_session_deleted")

    get root_path

    assert_response :success
    assert_select "h2", { text: "Withdrawn headline", count: 0 },
      "the plan itself is gone, not merely annotated"
    assert_select ".withdrawn-note", 0, "with no current plan there is nothing to contrast it against"
  end

  test "another user's withdrawn plan does not leak onto this dashboard" do
    theirs = users(:two).coaching_decisions.create!(
      decision_type: "daily_training",
      rule_key: DailyTrainingOrchestrator::RULE_KEY,
      rule_version: DailyTrainingOrchestrator::RULE_VERSION,
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "headline" => "Theirs", "guidance" => "Theirs", "lifts" => [] },
      citations: [], confidence: "high"
    )
    theirs.retract!(reason: "workout_session_deleted")
    daily_training_decision

    get root_path

    assert_select ".withdrawn-note", 0
  end

  test "a brand-new account is told what setup is still outstanding" do
    get root_path

    assert_response :success
    assert_select ".setup-panel", 1
    assert_select ".setup-step", 3
    assert_select ".setup-panel h2", text: "3 steps to your first plan."
    # The steps are ordered, so the first card is the one to do next.
    assert_equal [ "Set your training goal", "Add a training target", "Do your first check-in" ],
      css_select(".setup-step strong").map(&:text)
    # Nothing else links back to onboarding once a user has left it.
    assert_select "a[href=?]", onboarding_path
  end

  test "the setup panel drops steps as they are done" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current)

    get root_path

    assert_select ".setup-step", 2
    assert_select ".setup-panel h2", text: "2 steps to your first plan."
    assert_equal "Add a training target", css_select(".setup-step strong").first.text
  end

  test "the setup panel disappears once the engine has what it needs" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current)
    exercise = Exercise.create!(name: "Zzz Setup Squat", modality: "barbell")
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 6, rep_max: 8,
      target_rir_min: 1, target_rir_max: 2, increment_kg: 2.5,
      working_sets: 3, started_on: Date.current
    )

    get root_path

    assert_response :success
    assert_select ".setup-panel", 0
  end

  test "a set-up account is not nagged about an unpaired watch" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current)
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2
    )

    get root_path

    assert_select ".setup-panel", 0
  end

  def daily_training_decision(headline: "Run the plan as written")
    @user.coaching_decisions.create!(
      decision_type: "daily_training",
      rule_key: DailyTrainingOrchestrator::RULE_KEY,
      rule_version: DailyTrainingOrchestrator::RULE_VERSION,
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: {
        "status" => "push",
        "headline" => headline,
        "guidance" => "Guidance text.",
        "readiness_score" => 77,
        "lifts" => []
      },
      citations: [],
      confidence: "high"
    )
  end

  test "revoking a device is styled and confirmed like the destructive action it is" do
    WearableDevice.issue_for!(user: @user, platform: "ios_healthkit", external_id: "device-1", name: "Watch")

    get root_path

    assert_response :success
    assert_select "button.text-button--danger", text: "Revoke device"
    assert_select "form[data-turbo-confirm]", minimum: 1
  end

  test "the wearable copy names everything a paired device now sends" do
    get root_path

    assert_response :success
    # Ingestion widened past readiness; the pitch for pairing had not.
    assert_select ".wearable-status p", text: /workouts, weigh-ins, steps and energy/
  end
end
