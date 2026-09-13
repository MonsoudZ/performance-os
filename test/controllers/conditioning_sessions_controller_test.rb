require "test_helper"

class ConditioningSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "renders the conditioning workspace" do
    get conditioning_sessions_path

    assert_response :success
    assert_select "h1", "Train the engine."
  end

  test "logs a session with entered units converted to canonical" do
    assert_difference "ConditioningSession.count", 1 do
      post conditioning_sessions_path, params: {
        conditioning_session: { activity_type: "run", performed_at: Time.current, duration_minutes: 45, distance_meters: 8, avg_hr_bpm: 150 }
      }
    end

    session = @user.conditioning_sessions.order(:id).last
    assert_equal 2700, session.duration_seconds
    assert_equal 8000, session.distance_meters
    assert_redirected_to conditioning_sessions_path
  end

  test "logging a session recomputes today's training plan" do
    assert_enqueued_with(job: TrainingPlanRecomputeJob) do
      post conditioning_sessions_path, params: {
        conditioning_session: { activity_type: "run", performed_at: Time.current, duration_minutes: 30 }
      }
    end
  end

  test "rejects an unknown activity type" do
    assert_no_difference "ConditioningSession.count" do
      post conditioning_sessions_path, params: {
        conditioning_session: { activity_type: "teleport", performed_at: Time.current, duration_minutes: 30 }
      }
    end

    assert_response :unprocessable_entity
  end

  test "deletes a session" do
    session = @user.conditioning_sessions.create!(activity_type: "run", performed_at: Time.current, duration_seconds: 1800)

    assert_difference "ConditioningSession.count", -1 do
      delete conditioning_session_path(session)
    end

    assert_redirected_to conditioning_sessions_path
  end

  test "cannot delete another user's session" do
    other = users(:two).conditioning_sessions.create!(activity_type: "run", performed_at: Time.current, duration_seconds: 1800)

    delete conditioning_session_path(other)

    assert_response :not_found
    assert ConditioningSession.exists?(other.id)
  end

  test "sets max HR through the profile" do
    # The inline form lives on the conditioning page, so it returns there.
    patch profile_path,
      params: { user: { max_hr: 188 } },
      headers: { "HTTP_REFERER" => conditioning_sessions_url }

    assert_equal 188, @user.reload.max_hr
    assert_redirected_to conditioning_sessions_path
  end

  test "a session that arrived from a watch says so" do
    device, = WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit", external_id: "device-1", name: "Watch"
    )
    sample = device.wearable_samples.create!(
      user: @user, external_id: "workout-1", metric_type: "workout",
      started_at: 2.hours.ago, ended_at: 1.hour.ago, value: 2_400, unit: "seconds"
    )
    @user.conditioning_sessions.create!(
      wearable_sample: sample, performed_at: 2.hours.ago, activity_type: "run", duration_seconds: 2_400
    )
    @user.conditioning_sessions.create!(
      performed_at: 3.hours.ago, activity_type: "row", duration_seconds: 1_200
    )

    get conditioning_sessions_path

    assert_response :success
    assert_select ".compact-list__item strong .pill", 1
  end
end
