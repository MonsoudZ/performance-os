require "test_helper"

class ConditioningSessionTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "duration and distance accessors convert to canonical units" do
    session = @user.conditioning_sessions.new(activity_type: "run", performed_at: Time.current)
    session.duration_minutes = 48
    session.distance_km = 8

    assert_equal 2880, session.duration_seconds
    assert_equal 8000, session.distance_meters
    assert_equal 48.0, session.duration_minutes
    assert_equal 8.0, session.distance_km
  end

  test "pace per km for distance-based activities" do
    session = build(activity_type: "run", duration_seconds: 2880, distance_meters: 8000)

    # 2880s over 8km = 360 s/km = 6:00 /km
    assert_equal 360, session.pace_seconds_per_km
  end

  test "no pace for activities without distance" do
    assert_nil build(activity_type: "jump", duration_seconds: 600).pace_seconds_per_km
  end

  test "hr_zone classifies average HR against max HR" do
    @user.update!(max_hr: 190)

    assert_equal "Z2", build(avg_hr_bpm: 125).hr_zone # 0.66
    assert_equal "Z4", build(avg_hr_bpm: 165).hr_zone # 0.87
    assert_equal "Z5", build(avg_hr_bpm: 185).hr_zone # 0.97
  end

  test "hr_zone is nil without max HR or average HR" do
    assert_nil build(avg_hr_bpm: 130).hr_zone(nil)
    assert_nil build.hr_zone(190)
  end

  private

  def build(attributes = {})
    @user.conditioning_sessions.new({ activity_type: "run", performed_at: Time.current, duration_seconds: 600 }.merge(attributes))
  end
end
