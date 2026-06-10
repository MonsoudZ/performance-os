require "test_helper"

class WearableSyncIngestorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @device, = WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit", external_id: "device-1", name: "iPhone"
    )
  end

  test "raises before inserting when the batch exceeds the cap" do
    oversized = Array.new(WearableSyncIngestor::MAX_BATCH_SIZE + 1) { {} }

    assert_no_difference "WearableSample.count" do
      assert_raises(ArgumentError) { WearableSyncIngestor.new(@device, samples: oversized).call }
    end
  end

  test "passes through a measured value for non-sleep metrics" do
    result = WearableSyncIngestor.new(@device, samples: [ hrv_sample(value: 52.5) ]).call

    assert_equal 1, result[:inserted]
    assert_equal 52.5, @device.wearable_samples.find_by(external_id: "hrv-1").value.to_f
  end

  test "computes sleep minutes from the interval when the value is blank" do
    WearableSyncIngestor.new(@device, samples: [
      sleep_sample(value: nil, started: "2026-06-09T22:00:00Z", ended: "2026-06-10T05:30:00Z")
    ]).call

    # 22:00 -> 05:30 next day = 7.5 hours = 450 minutes.
    assert_equal 450.0, @device.wearable_samples.find_by(external_id: "sleep-1").value.to_f
  end

  test "keeps an explicit sleep value over the computed interval" do
    WearableSyncIngestor.new(@device, samples: [
      sleep_sample(value: 400, started: "2026-06-09T22:00:00Z", ended: "2026-06-10T05:30:00Z")
    ]).call

    assert_equal 400.0, @device.wearable_samples.find_by(external_id: "sleep-1").value.to_f
  end

  test "buckets sleep by the local date of its end time" do
    # Ends 05:30 UTC = 23:30 the previous day in Denver (UTC-6), so it lands on June 9.
    result = WearableSyncIngestor.new(@device, samples: [
      sleep_sample(value: 450, started: "2026-06-09T22:00:00Z", ended: "2026-06-10T05:30:00Z")
    ]).call

    assert_equal [ Date.new(2026, 6, 9) ], result[:materialized_dates]
  end

  test "buckets non-sleep metrics by the local date of their start time" do
    result = WearableSyncIngestor.new(@device, samples: [
      hrv_sample(value: 50, started: "2026-06-10T13:00:00Z")
    ]).call

    # 13:00 UTC = 07:00 Denver, same day.
    assert_equal [ Date.new(2026, 6, 10) ], result[:materialized_dates]
  end

  test "replaying the same external ids is idempotent" do
    samples = [ hrv_sample(value: 52.5) ]
    WearableSyncIngestor.new(@device, samples: samples).call

    result = WearableSyncIngestor.new(@device, samples: samples).call

    assert_equal 0, result[:inserted]
    assert_equal 1, result[:duplicates]
  end

  private

  def hrv_sample(value:, started: "2026-06-10T13:00:00Z")
    {
      "external_id" => "hrv-1",
      "metric_type" => "hrv_sdnn_ms",
      "started_at" => started,
      "value" => value
    }
  end

  def sleep_sample(value:, started:, ended:)
    {
      "external_id" => "sleep-1",
      "metric_type" => "sleep_asleep",
      "started_at" => started,
      "ended_at" => ended,
      "value" => value
    }
  end
end
