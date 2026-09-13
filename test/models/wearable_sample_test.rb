require "test_helper"

class WearableSampleTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @device, = WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit", external_id: "device-1", name: "Watch"
    )
  end

  test "every metric the model accepts has a canonical unit" do
    assert_equal WearableSample::METRIC_UNITS.keys.sort, WearableSample::METRIC_UNITS.keys.uniq.sort
    WearableSample::METRIC_UNITS.each_value { |unit| assert_predicate unit, :present? }
  end

  test "a sample whose unit disagrees with its metric is rejected" do
    sample = build(metric_type: "body_mass_kg", unit: "lb")

    assert_not sample.valid?
    assert_includes sample.errors[:unit], "must be canonical for the metric"
  end

  test "the database refuses a metric type the model would have caught" do
    sample = build(metric_type: "hrv_sdnn_ms")
    sample.save!

    # Bypassing the model is the point: the constraint is the backstop.
    assert_raises(ActiveRecord::StatementInvalid) do
      WearableSample.where(id: sample.id).update_all(metric_type: "blood_glucose_mgdl")
    end
  end

  test "body mass is stored at the same scale as every other weight in the app" do
    sample = build(metric_type: "body_mass_kg", value: BigDecimal("81.646627"))
    sample.save!

    # Anything coarser and a pound entered to four decimals changes when it
    # round-trips, which is the whole reason WEIGHT_SCALE is 6.
    assert_equal BigDecimal("81.646627"), sample.reload.value
  end

  test "sleep is dated by when it ended and everything else by when it started" do
    night = build(metric_type: "sleep_asleep", external_id: "sleep-1",
      started_at: Time.utc(2026, 6, 9, 22), ended_at: Time.utc(2026, 6, 10, 5, 30), value: 450)
    workout = build(metric_type: "workout", external_id: "workout-1",
      started_at: Time.utc(2026, 6, 10, 13), ended_at: Time.utc(2026, 6, 10, 14), value: 3_600)

    assert_equal Time.utc(2026, 6, 10, 5, 30), night.dated_at
    assert_equal Time.utc(2026, 6, 10, 13), workout.dated_at
  end

  test "only steps and energy are daily totals" do
    assert WearableSample.daily_total?("step_count")
    assert WearableSample.daily_total?("active_energy_kcal")
    assert WearableSample.daily_total?("basal_energy_kcal")
    assert_not WearableSample.daily_total?("workout")
    assert_not WearableSample.daily_total?("body_mass_kg")
  end

  test "a sample cannot be filed under another user's device" do
    sample = build
    sample.user = users(:two)

    assert_not sample.valid?
    assert_includes sample.errors[:wearable_device], "must belong to the same user"
  end

  private

  def build(metric_type: "hrv_sdnn_ms", unit: nil, external_id: "sample-1", value: 50, **attributes)
    @device.wearable_samples.new(
      {
        user: @user,
        external_id: external_id,
        metric_type: metric_type,
        started_at: Time.utc(2026, 6, 10, 13),
        value: value,
        unit: unit || WearableSample::METRIC_UNITS.fetch(metric_type)
      }.merge(attributes)
    )
  end
end
