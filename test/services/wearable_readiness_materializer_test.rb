require "test_helper"

class WearableReadinessMaterializerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @device, = WearableDevice.issue_for!(
      user: @user,
      platform: "ios_healthkit",
      external_id: "installation-123",
      name: "Mon’s iPhone"
    )
  end

  test "merges objective data into an existing subjective check-in" do
    date = Date.new(2026, 6, 9)
    @user.daily_readiness_inputs.create!(
      metric_date: date,
      soreness: 2,
      fatigue: 3,
      stress: 2,
      source: "manual"
    )
    create_sample("hrv-1", "hrv_sdnn_ms", Time.utc(2026, 6, 9, 15), 60)

    readiness, = WearableReadinessMaterializer.new(@user, metric_date: date).call

    assert_equal 2, readiness.soreness
    assert_equal 60, readiness.hrv_sdnn_ms.to_f
    assert_equal "mixed", readiness.source
  end

  # A night the watch measured is watch data even though nothing about the row
  # says so once it is in the column — sleep somebody typed looks identical — so
  # the materializer has to declare its own write rather than leave the row to
  # work it out. A sleep-only sync that came back "manual" would make
  # `sleep_from_watch?` false and stop the dashboard saying where the figure
  # came from.
  test "a night only sleep synced for is the watch's, and is not an answered day" do
    date = Date.new(2026, 6, 9)
    create_sample("sleep-1", "sleep_asleep", Time.utc(2026, 6, 9, 9), 447)

    readiness, = WearableReadinessMaterializer.new(@user, metric_date: date).call

    assert_equal "healthkit", readiness.source
    assert_equal 447, readiness.sleep_minutes
    assert readiness.sleep_from_watch?
    # Scoring a day nobody answered is the failure this whole rule exists to
    # prevent, so it must not read as checked in.
    assert_not readiness.checked_in?
  end

  test "unlocks objective baselines after seven prior observations" do
    7.times do |index|
      date = Date.new(2026, 6, 1) + index.days
      @user.daily_readiness_inputs.create!(
        metric_date: date,
        hrv_sdnn_ms: 50 + index,
        resting_hr: 60 - index,
        sleep_minutes: 450,
        source: "healthkit"
      )
    end
    target_date = Date.new(2026, 6, 8)
    create_sample("hrv-target", "hrv_sdnn_ms", Time.utc(2026, 6, 8, 15), 58)
    create_sample("rhr-target", "resting_hr_bpm", Time.utc(2026, 6, 8, 15), 52)

    _, _, decision = WearableReadinessMaterializer.new(@user, metric_date: target_date).call

    assert decision.inputs.dig("objective_baselines", "hrv_sdnn_ms")
    assert decision.inputs.dig("objective_baselines", "resting_hr")
    assert decision.inputs["hrv_sdnn_ms"]
  end

  private

  def create_sample(external_id, metric_type, started_at, value)
    @device.wearable_samples.create!(
      user: @user,
      external_id: external_id,
      metric_type: metric_type,
      started_at: started_at,
      ended_at: started_at,
      value: value,
      unit: WearableSample::METRIC_UNITS.fetch(metric_type)
    )
  end
end
