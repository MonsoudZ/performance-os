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
        # Materialization is deferred to a job; perform it so the readiness input
        # and decision asserted below exist after the request.
        perform_enqueued_jobs do
          post api_v1_wearable_sync_path,
            params: { samples: samples },
            headers: authorization_header,
            as: :json
        end
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

  test "a synced workout, weigh-in and day of energy land as records the app already reads" do
    travel_to @instant do
      perform_enqueued_jobs do
        post api_v1_wearable_sync_path,
          params: { samples: activity_samples },
          headers: authorization_header,
          as: :json
      end
    end

    assert_response :accepted
    session = @user.conditioning_sessions.sole
    assert_equal "run", session.activity_type
    assert_equal 8_000, session.distance_meters

    weigh_in = @user.body_metrics.sole
    assert_equal "healthkit", weigh_in.source
    assert_equal BigDecimal("81.646627"), weigh_in.weight_kg
    assert_equal BigDecimal("81.646627"), @user.weight_trends.sole.raw_kg

    # The pinned clock is 23:30 on June 9 in Denver, so June 8 is the most recent
    # complete local day and the only one whose energy can be believed.
    estimate = @user.expenditure_estimates.take
    assert_equal "wearable_energy", estimate.basis
    assert_equal 2_400, estimate.estimated_tdee.to_f
  end

  test "rejects a metric type the server does not model without saying why" do
    post api_v1_wearable_sync_path,
      params: { samples: [ samples.first.merge(metric_type: "blood_glucose_mgdl") ] },
      headers: authorization_header,
      as: :json

    assert_response :unprocessable_entity
    assert_equal({ "error" => "Sync rejected" }, response.parsed_body)
    assert_equal 0, WearableSample.count
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

  # 06:00 on June 8 in Denver — a local day already complete at the pinned clock.
  def activity_samples
    day_start = Time.utc(2026, 6, 8, 12)
    [
      {
        external_id: "workout-1",
        metric_type: "workout",
        started_at: day_start.iso8601,
        ended_at: (day_start + 40.minutes).iso8601,
        value: 2_400,
        metadata: { activity_type: "run", distance_meters: "8000", avg_hr_bpm: "152" }
      },
      {
        external_id: "mass-1",
        metric_type: "body_mass_kg",
        started_at: day_start.iso8601,
        value: "81.646627"
      },
      {
        external_id: "active_energy_kcal:2026-06-08",
        metric_type: "active_energy_kcal",
        started_at: day_start.iso8601,
        value: 620
      },
      {
        external_id: "basal_energy_kcal:2026-06-08",
        metric_type: "basal_energy_kcal",
        started_at: day_start.iso8601,
        value: 1_780
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
