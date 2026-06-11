module ReadinessHelper
  SLEEP_QUARTER_HOUR_RANGE = (8..52).freeze # 2h00 .. 13h00 in 15-minute steps

  # [label, decimal-hours] pairs for the sleep dropdown. A watch-synced value
  # that doesn't land on the 15-minute grid is added so it stays selectable.
  def sleep_hour_options(current = nil)
    options = SLEEP_QUARTER_HOUR_RANGE.map do |quarter_hours|
      hours = quarter_hours / 4.0
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
