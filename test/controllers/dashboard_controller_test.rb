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
    assert_select "input[name='daily_readiness_input[sleep_hours]']"
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
    assert_select "input[name='daily_readiness_input[sleep_hours]']", count: 0
    assert_select ".synced-note"
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
end
