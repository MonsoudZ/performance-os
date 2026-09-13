require "test_helper"

class WearableActivitySummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @device, = WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit", external_id: "device-1", name: "Watch"
    )
    @date = Date.new(2026, 6, 10)
  end

  test "reports nothing for a day the device said nothing about" do
    assert_not WearableActivitySummary.new(@user, on: @date).call.any?
  end

  test "reports the day's steps and both halves of its energy" do
    create_total("step_count", 11_500)
    create_total("active_energy_kcal", 620)
    create_total("basal_energy_kcal", 1_780)

    summary = WearableActivitySummary.new(@user, on: @date).call

    assert summary.any?
    assert_equal 11_500, summary.steps
    assert_equal 2_400, summary.total_energy_kcal
  end

  test "withholds a total when the device only reported half of it" do
    create_total("active_energy_kcal", 620)

    summary = WearableActivitySummary.new(@user, on: @date).call

    assert summary.any?
    # Active energy alone is not a day's expenditure, and printing it as one
    # would make a 620 kcal day look like the whole story.
    assert_nil summary.total_energy_kcal
  end

  test "counts by the reader's local day, not the server's" do
    # 05:00 UTC on June 11 is 23:00 on June 10 in Denver.
    create_total("step_count", 11_500, at: Time.utc(2026, 6, 11, 5))

    assert_equal 11_500, WearableActivitySummary.new(@user, on: @date).call.steps
    assert_nil WearableActivitySummary.new(@user, on: @date + 1).call.steps
  end

  private

  def create_total(metric_type, value, at: Time.utc(2026, 6, 10, 13))
    @device.wearable_samples.create!(
      user: @user,
      external_id: "#{metric_type}:#{@date}",
      metric_type: metric_type,
      started_at: at,
      value: value,
      unit: WearableSample::METRIC_UNITS.fetch(metric_type)
    )
  end
end
