module ConditioningHelper
  def format_pace(seconds_per_km)
    return "—" if seconds_per_km.blank?

    "#{seconds_per_km / 60}:#{format('%02d', seconds_per_km % 60)} /km"
  end

  def format_duration(minutes)
    return "—" if minutes.blank?

    hours, mins = minutes.divmod(60)
    hours.positive? ? "#{hours}h #{mins}m" : "#{mins}m"
  end

  # A one-line headline tuned to what the active goal cares about.
  def conditioning_goal_headline(goal, summary)
    case goal&.goal_type
    when "marathon"
      "#{summary.total_distance_km} km logged this week"
    when "longevity"
      "#{summary.zone2_minutes} min in Zone 2 this week"
    when "vertical_jump"
      jumps = summary.by_activity.values_at("jump", "plyometric").compact.sum
      "#{pluralize(jumps, 'jump/plyo session')} this week"
    when "athletic_performance"
      "#{pluralize(summary.session_count, 'conditioning session')} this week"
    else
      "#{pluralize(summary.session_count, 'session')} · #{summary.total_distance_km} km this week"
    end
  end
end
