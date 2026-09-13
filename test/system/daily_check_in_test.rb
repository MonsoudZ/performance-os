require "application_system_test_case"

# The check-in is the product's entry point: it is the write that starts the
# whole recompute pipeline, and the dashboard shows a placeholder until a
# background job finishes and broadcasts a refresh. That handoff — form, job,
# Turbo morph — only exists in a browser.
class DailyCheckInTest < ApplicationSystemTestCase
  setup { @user = users(:one) }

  test "a check-in writes a readiness decision and the dashboard picks it up" do
    sign_in @user

    assert_text "Your plan starts with sixty seconds"

    complete_check_in

    # The plan is computed off the request, so the user sees a placeholder first.
    assert_text "Generating today’s plan", wait: 5
    assert_equal 1, @user.daily_readiness_inputs.count

    perform_enqueued_jobs

    decision = @user.coaching_decisions.of_type("daily_readiness").latest_first.first

    assert_not_nil decision, "the check-in produced a readiness decision"
    assert_includes %w[push steady recover], decision.output["status"]

    # The page updates itself when the broadcast lands; reloading asserts the
    # same state without depending on websocket timing.
    visit root_path

    assert_no_text "Generating today’s plan"
    # The dashboard must render the plan the orchestrator actually wrote.
    assert_text @user.coaching_decisions.of_type("daily_training").latest_first.first.output["headline"]
    assert_selector ".score-card strong", text: @user.readiness_scores.order(:score_date).last.score.to_s
  end

  test "a second visit shows the check-in as done rather than offering it again" do
    sign_in @user
    complete_check_in

    assert_text "Generating today’s plan", wait: 5

    visit root_path

    assert_text "Today’s check-in is complete"
    assert_no_button "Generate today’s plan"
  end

  test "an incomplete check-in is refused by the browser rather than submitted" do
    sign_in @user

    # Every rating is required, so leaving them blank must not reach the server.
    assert_no_difference -> { @user.daily_readiness_inputs.count } do
      click_on "Generate today’s plan"
      assert_text "How’s the system running?", wait: 2
    end
  end

  private

  def complete_check_in
    within ".check-in__form" do
      select "7h 30m", from: "Sleep duration" if has_select?("Sleep duration")
      choose_rating "Sleep quality", 4
      choose_rating "Muscle soreness", 2
      choose_rating "General fatigue", 2
      choose_rating "Life stress", 2
      click_on "Generate today’s plan"
    end
  end

  # Each rating is a 1–5 radio group whose visible label is just the number.
  def choose_rating(legend, value)
    find("fieldset", text: legend).find("label", text: value.to_s, match: :prefer_exact).click
  end
end
