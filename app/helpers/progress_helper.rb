module ProgressHelper
  # Server-rendered SVG line of estimated-1RM over time, with PR points marked.
  # No inline JS or styles, so it stays within the enforced CSP.
  def e1rm_sparkline(points, width: 220, height: 48)
    return tag.span("Not enough sessions yet", class: "muted") if points.size < 2

    values = points.map(&:e1rm)
    min, max = values.minmax
    span = (max - min).zero? ? 1.0 : (max - min)
    step = points.size > 1 ? width.to_f / (points.size - 1) : 0
    pad = 4

    coords = points.each_with_index.map do |point, index|
      x = (index * step).round(2)
      y = (height - pad - ((point.e1rm - min) / span * (height - 2 * pad))).round(2)
      [ x, y, point.pr ]
    end

    tag.svg(viewBox: "0 0 #{width} #{height}", width: width, height: height, class: "sparkline", role: "img",
      aria: { label: "Estimated 1RM trend" }) do
      line = tag.polyline(points: coords.map { |x, y, _| "#{x},#{y}" }.join(" "),
        fill: "none", stroke: "currentColor", "stroke-width": "2")
      markers = safe_join(coords.select { |_, _, pr| pr }.map do |x, y, _|
        tag.circle(cx: x, cy: y, r: "3.5", fill: "currentColor")
      end)
      safe_join([ line, markers ])
    end
  end

  # Generic server-rendered SVG line over a series of numbers (CSP-clean).
  def line_chart(values, width: 320, height: 80)
    return tag.span("Not enough data yet", class: "muted") if values.size < 2

    min, max = values.minmax
    span = (max - min).zero? ? 1.0 : (max - min)
    step = width.to_f / (values.size - 1)
    pad = 6

    coords = values.each_with_index.map do |value, index|
      x = (index * step).round(2)
      y = (height - pad - ((value - min) / span * (height - 2 * pad))).round(2)
      "#{x},#{y}"
    end

    tag.svg(viewBox: "0 0 #{width} #{height}", width: width, height: height, class: "line-chart", role: "img",
      aria: { label: "Trend" }) do
      tag.polyline(points: coords.join(" "), fill: "none", stroke: "currentColor", "stroke-width": "2")
    end
  end

  # Position (0..100%) of a set count along the volume axis for inline-width bars.
  def volume_axis_percent(value, axis_max)
    return 0 if axis_max.to_f.zero?

    [ (value.to_f / axis_max * 100).round(1), 100 ].min
  end

  def volume_status_label(status)
    {
      "under" => "Below minimum",
      "in_range" => "Productive",
      "over" => "Over maximum",
      "untracked" => "No landmark"
    }.fetch(status, status)
  end
end
