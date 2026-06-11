require "test_helper"

class DailyReadinessInputTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "sleep_hours reads and writes minutes" do
    input = @user.daily_readiness_inputs.new
    input.sleep_hours = 7.5
    assert_equal 450, input.sleep_minutes
    assert_equal 7.5, input.sleep_hours
  end

  test "blank sleep_hours clears minutes" do
    input = @user.daily_readiness_inputs.new(sleep_minutes: 400)
    input.sleep_hours = ""
    assert_nil input.sleep_minutes
  end

  test "checked_in? requires every subjective tap" do
    input = @user.daily_readiness_inputs.new(sleep_minutes: 450, source: "healthkit")
    assert_not input.checked_in?, "objective-only data is not a completed check-in"

    input.assign_attributes(sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3)
    assert input.checked_in?
  end

  test "sleep_from_watch? reflects watch-sourced sleep only" do
    assert @user.daily_readiness_inputs.new(sleep_minutes: 450, source: "healthkit").sleep_from_watch?
    assert @user.daily_readiness_inputs.new(sleep_minutes: 450, source: "mixed").sleep_from_watch?
    assert_not @user.daily_readiness_inputs.new(sleep_minutes: 450, source: "manual").sleep_from_watch?
    assert_not @user.daily_readiness_inputs.new(source: "healthkit").sleep_from_watch?
  end
end
