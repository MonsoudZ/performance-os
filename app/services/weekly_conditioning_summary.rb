class WeeklyConditioningSummary
  Summary = Data.define(
    :session_count, :total_distance_km, :total_duration_minutes,
    :zone_minutes, :zone2_minutes, :by_activity
  )

  def initialize(user, week_start: nil)
    @user = user
    @week_start = week_start || user.local_date.beginning_of_week # Monday
  end

  def call
    sessions = week_sessions

    Summary.new(
      session_count: sessions.size,
      total_distance_km: (sessions.sum { |s| s.distance_meters.to_i } / 1000.0).round(1),
      total_duration_minutes: (sessions.sum(&:duration_seconds) / 60.0).round,
      zone_minutes: zone_minutes(sessions),
      zone2_minutes: zone_minutes(sessions)["Z2"] || 0,
      by_activity: sessions.group_by(&:activity_type).transform_values(&:size)
    )
  end

  def week_start = @week_start
  def week_end = @week_start + 6.days

  private

  attr_reader :user

  def week_sessions
    @week_sessions ||= user.conditioning_sessions
      .performed_between(user.local_day_range(week_start).begin..user.local_day_range(week_end).end)
      .to_a
  end

  # Whole-session duration attributed to that session's HR zone.
  def zone_minutes(sessions)
    sessions.each_with_object(Hash.new(0)) do |session, totals|
      zone = session.hr_zone(user.max_hr)
      next unless zone

      totals[zone] += (session.duration_seconds / 60.0).round
    end
  end
end
