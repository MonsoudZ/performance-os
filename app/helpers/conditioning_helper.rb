module ConditioningHelper
  def format_duration(minutes)
    return "—" if minutes.blank?

    hours, mins = minutes.divmod(60)
    hours.positive? ? "#{hours}h #{mins}m" : "#{mins}m"
  end

  # A conditioning directive's `done` and `target` are canonical: metres for the
  # distance metric, minutes or sessions otherwise. Render whichever it is in the
  # reader's units.
  def conditioning_amount(metric, value)
    return if value.nil?

    metric.to_s == "distance" ? distance(value) : value
  end

  # The directive stores no progress sentence, so the view composes one. That
  # keeps kilometres out of an immutable decision and lets an imperial reader see
  # miles in the same breath.
  def conditioning_progress(conditioning)
    metric = conditioning["metric"]
    done = conditioning_amount(metric, conditioning["done"])
    target = conditioning_amount(metric, conditioning["target"])
    suffix = metric.to_s == "distance" ? "" : " #{conditioning['label']}"

    "You're at #{done} of #{target}#{suffix} this week."
  end

  # A one-line headline tuned to what the active goal cares about.
  def conditioning_goal_headline(goal, summary)
    case goal&.goal_type
    when "marathon"
      "#{distance(summary.total_distance_meters)} logged this week"
    when "longevity"
      "#{summary.zone2_minutes} min in Zone 2 this week"
    when "vertical_jump"
      jumps = summary.by_activity.values_at("jump", "plyometric").compact.sum
      "#{pluralize(jumps, 'jump/plyo session')} this week"
    when "athletic_performance"
      "#{pluralize(summary.session_count, 'conditioning session')} this week"
    else
      "#{pluralize(summary.session_count, 'session')} · #{distance(summary.total_distance_meters)} this week"
    end
  end
end
