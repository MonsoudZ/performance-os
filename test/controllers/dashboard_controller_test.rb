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
end
