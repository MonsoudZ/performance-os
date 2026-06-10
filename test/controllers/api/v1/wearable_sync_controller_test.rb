require "test_helper"

class Api::V1::WearableSyncControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @device, @access_token = WearableDevice.issue_for!(
      user: @user,
      platform: "ios_healthkit",
      external_id: "installation-123",
      name: "Mon’s iPhone"
    )
    @instant = Time.utc(2026, 6, 10, 5, 30)
  end

  teardown { Rack::Attack.reset! }

  test "rejects a missing bearer token" do
    post api_v1_wearable_sync_path, params: { samples: [] }, as: :json

    assert_response :unauthorized
  end

  test "ingests canonical samples and materializes local-day readiness" do
    travel_to @instant do
      assert_difference "WearableSample.count", 3 do
        post api_v1_wearable_sync_path,
          params: { samples: samples },
          headers: authorization_header,
          as: :json
      end
    end

    assert_response :accepted
    assert_equal 3, response.parsed_body.fetch("inserted")
    readiness = @user.daily_readiness_inputs.find_by!(metric_date: Date.new(2026, 6, 9))
    assert_equal 52.5, readiness.hrv_sdnn_ms.to_f
    assert_equal 55, readiness.resting_hr
    assert_equal 450, readiness.sleep_minutes
    assert_equal "healthkit", readiness.source
    assert_equal "low", latest_readiness_decision.confidence
  end

  test "replaying HealthKit UUIDs is idempotent" do
    travel_to @instant do
      post api_v1_wearable_sync_path,
        params: { samples: samples },
        headers: authorization_header,
        as: :json

      assert_no_difference [ "WearableSample.count", "CoachingDecision.count", "ReadinessScore.count" ] do
        post api_v1_wearable_sync_path,
          params: { samples: samples },
          headers: authorization_header,
          as: :json
      end
    end

    assert_equal 0, response.parsed_body.fetch("inserted")
    assert_equal 3, response.parsed_body.fetch("duplicates")
  end

  test "throttles a device that floods the sync endpoint" do
    # Pin time so the rate-limit window is stable, then saturate the per-device
    # counter through Rack::Attack's own cache (the throttle keys on
    # "#{name}:#{discriminator}") instead of 60 real round-trips.
    travel_to @instant do
      counter_key = "api/v1/wearable_sync/device:#{@device.id}"
      Rack::Attack::WEARABLE_SYNC_LIMIT.times do
        Rack::Attack.cache.count(counter_key, Rack::Attack::WEARABLE_SYNC_PERIOD)
      end

      post api_v1_wearable_sync_path, params: { samples: [] }, headers: authorization_header, as: :json
      assert_response :too_many_requests
    end
  end

  test "revoked devices cannot sync" do
    @device.update!(revoked_at: Time.current)

    post api_v1_wearable_sync_path,
      params: { samples: samples },
      headers: authorization_header,
      as: :json

    assert_response :unauthorized
  end

  private

  def samples
    [
      {
        external_id: "hrv-1",
        metric_type: "hrv_sdnn_ms",
        started_at: @instant.iso8601,
        ended_at: @instant.iso8601,
        value: 52.5,
        metadata: { source_bundle: "com.apple.health" }
      },
      {
        external_id: "rhr-1",
        metric_type: "resting_hr_bpm",
        started_at: @instant.iso8601,
        ended_at: @instant.iso8601,
        value: 55
      },
      {
        external_id: "sleep-1",
        metric_type: "sleep_asleep",
        started_at: Time.utc(2026, 6, 9, 22, 0).iso8601,
        ended_at: Time.utc(2026, 6, 10, 5, 30).iso8601,
        value: 450
      }
    ]
  end

  def authorization_header
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def latest_readiness_decision
    @user.coaching_decisions.where(decision_type: "daily_readiness").order(:created_at).last
  end
end
