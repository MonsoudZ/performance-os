module ReadinessHelper
  SLEEP_HALF_HOUR_RANGE = (4..26).freeze # 2h00 .. 13h00 in 30-minute steps

  # [label, decimal-hours] pairs for the sleep dropdown. A watch-synced value
  # that doesn't land on the 30-minute grid is added so it stays selectable.
  def sleep_hour_options(current = nil)
    options = SLEEP_HALF_HOUR_RANGE.map do |half_hours|
      hours = half_hours / 2.0
      [ sleep_hours_label(hours), hours ]
    end

    if current.present? && options.none? { |_, value| value == current.to_f }
      options << [ sleep_hours_label(current), current.to_f ]
      options.sort_by!(&:last)
    end

    options
  end

  def sleep_hours_label(hours)
    whole = hours.to_i
    minutes = ((hours - whole) * 60).round
    minutes.zero? ? "#{whole}h" : "#{whole}h #{minutes}m"
  end
end
