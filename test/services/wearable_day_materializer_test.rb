require "test_helper"

# The whole point of widening ingestion: a watch and a scale should produce the
# same records a user would have produced by hand, so every rule downstream —
# weight trend, expenditure, conditioning targets — keeps working unchanged.
class WearableDayMaterializerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @device, = WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit", external_id: "device-1", name: "Watch"
    )
    @date = Date.new(2026, 6, 10)
  end

  test "a synced weigh-in becomes a body metric and moves the weight trend" do
    create_sample("mass-1", "body_mass_kg", value: "81.646627")

    WearableDayMaterializer.new(@user, metric_date: @date).call

    body_metric = @user.body_metrics.find_by!(measured_on: @date)
    assert_equal "healthkit", body_metric.source
    assert_equal BigDecimal("81.646627"), body_metric.weight_kg
    assert_equal BigDecimal("81.646627"), @user.weight_trends.find_by!(trend_date: @date).raw_kg
  end

  test "a day of weigh-ins is reduced by median, not by mean" do
    # Stepping off the scale early records a plausible-looking fraction of a
    # bodyweight. A mean of these three is 61 kg; the median is the real number.
    create_sample("mass-1", "body_mass_kg", value: "81.4")
    create_sample("mass-2", "body_mass_kg", value: "81.6", at: Time.utc(2026, 6, 10, 14))
    create_sample("mass-3", "body_mass_kg", value: "20.0", at: Time.utc(2026, 6, 10, 15))

    WearableDayMaterializer.new(@user, metric_date: @date).call

    assert_equal BigDecimal("81.4"), @user.body_metrics.find_by!(measured_on: @date).weight_kg
  end

  test "a synced weigh-in leaves a manual one for the same day alone" do
    manual = @user.body_metrics.create!(measured_on: @date, weight_kg: 80, source: "manual")
    create_sample("mass-1", "body_mass_kg", value: "81.5")

    WearableDayMaterializer.new(@user, metric_date: @date).call

    assert_equal BigDecimal("80"), manual.reload.weight_kg
    assert_equal 2, @user.body_metrics.where(measured_on: @date).count
  end

  test "a synced workout becomes a conditioning session" do
    create_sample(
      "workout-1", "workout", value: 2_400, at: Time.utc(2026, 6, 10, 13),
      metadata: { "activity_type" => "run", "distance_meters" => "8000", "avg_hr_bpm" => "152" }
    )

    WearableDayMaterializer.new(@user, metric_date: @date).call

    session = @user.conditioning_sessions.sole
    assert_equal "run", session.activity_type
    assert_equal 2_400, session.duration_seconds
    assert_equal 8_000, session.distance_meters
    assert_equal 152, session.avg_hr_bpm
    assert_predicate session, :synced?
  end

  test "re-materializing a day does not duplicate a workout already imported" do
    create_sample("workout-1", "workout", value: 2_400, at: Time.utc(2026, 6, 10, 13),
      metadata: { "activity_type" => "run" })

    assert_difference "ConditioningSession.count", 1 do
      2.times { WearableDayMaterializer.new(@user, metric_date: @date).call }
    end
  end

  test "a correction made by hand to an imported session survives the next sync" do
    create_sample("workout-1", "workout", value: 2_400, at: Time.utc(2026, 6, 10, 13),
      metadata: { "activity_type" => "other" })
    WearableDayMaterializer.new(@user, metric_date: @date).call
    @user.conditioning_sessions.sole.update!(activity_type: "row")

    WearableDayMaterializer.new(@user, metric_date: @date).call

    assert_equal "row", @user.conditioning_sessions.sole.activity_type
  end

  test "an activity the device could not name still counts as a session" do
    create_sample("workout-1", "workout", value: 1_800, at: Time.utc(2026, 6, 10, 13),
      metadata: { "activity_type" => "curling" })

    WearableDayMaterializer.new(@user, metric_date: @date).call

    assert_equal "other", @user.conditioning_sessions.sole.activity_type
  end

  test "a zero-length workout is not a session" do
    create_sample("workout-1", "workout", value: 0, at: Time.utc(2026, 6, 10, 13))

    WearableDayMaterializer.new(@user, metric_date: @date).call

    assert_empty @user.conditioning_sessions
  end

  test "a day that synced only steps does not invent a readiness check-in" do
    create_sample("step_count:2026-06-10", "step_count", value: 11_500)

    WearableDayMaterializer.new(@user, metric_date: @date).call

    # An unanswered day on the record as an answered one would be scored, and a
    # score built from nothing is worse than no score.
    assert_nil @user.daily_readiness_inputs.find_by(metric_date: @date)
  end

  test "a day with objective readiness data still produces a check-in" do
    create_sample("hrv-1", "hrv_sdnn_ms", value: 58)

    WearableDayMaterializer.new(@user, metric_date: @date).call

    assert_equal 58, @user.daily_readiness_inputs.find_by!(metric_date: @date).hrv_sdnn_ms.to_f
  end

  private

  def create_sample(external_id, metric_type, value:, at: Time.utc(2026, 6, 10, 13), metadata: {})
    @device.wearable_samples.create!(
      user: @user,
      external_id: external_id,
      metric_type: metric_type,
      started_at: at,
      ended_at: at,
      value: value,
      unit: WearableSample::METRIC_UNITS.fetch(metric_type),
      metadata: metadata
    )
  end
end
