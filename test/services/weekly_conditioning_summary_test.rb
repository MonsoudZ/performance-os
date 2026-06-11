require "test_helper"

class WeeklyConditioningSummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(max_hr: 190)
  end

  test "aggregates the week's sessions, distance, time, and zone-2 minutes" do
    @user.conditioning_sessions.create!(activity_type: "run", performed_at: Time.current, duration_seconds: 1800, distance_meters: 5000, avg_hr_bpm: 125) # 30 min Z2
    @user.conditioning_sessions.create!(activity_type: "bike", performed_at: Time.current, duration_seconds: 2400, distance_meters: 12000, avg_hr_bpm: 165) # 40 min Z4
    @user.conditioning_sessions.create!(activity_type: "run", performed_at: 8.days.ago, duration_seconds: 1800, distance_meters: 5000) # last week, excluded

    summary = WeeklyConditioningSummary.new(@user).call

    assert_equal 2, summary.session_count
    assert_equal 17.0, summary.total_distance_km # 5 + 12
    assert_equal 70, summary.total_duration_minutes # 30 + 40
    assert_equal 30, summary.zone2_minutes
    assert_equal({ "run" => 1, "bike" => 1 }, summary.by_activity)
  end

  test "empty week summarizes to zeros" do
    summary = WeeklyConditioningSummary.new(@user).call

    assert_equal 0, summary.session_count
    assert_equal 0.0, summary.total_distance_km
    assert_equal 0, summary.zone2_minutes
  end
end
