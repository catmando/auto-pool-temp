module ChartHelper
  SERIES = [
    { key: "air", label: "Air (hourly)", css: "air" },
    { key: "smoothed_air", label: "Air (24h avg)", css: "smoothed" },
    { key: "desired", label: "Ideal pool", css: "desired" },
    { key: "plan", label: "Plan", css: "plan" }
  ].freeze

  # Inline SVG line chart of a recommendation's forecast series.
  def forecast_chart(recommendation, width: 720, height: 260)
    rows = recommendation.series
    return tag.p("No forecast data.", class: "muted") if rows.size < 2

    pad_l, pad_r, pad_t, pad_b = 36, 8, 8, 24
    times = rows.map { |r| Time.zone.parse(r["t"]).to_f }
    keys = SERIES.map { |s| s[:key] }.select { |k| rows.first.key?(k) }
    values = rows.flat_map { |r| keys.map { |k| r[k].to_f } }
    lo = (values.min / 10).floor * 10
    hi = (values.max / 10).ceil * 10
    hi += 10 if hi == lo

    x = ->(t) { pad_l + (t - times.first) / (times.last - times.first) * (width - pad_l - pad_r) }
    y = ->(v) { pad_t + (hi - v) / (hi - lo).to_f * (height - pad_t - pad_b) }

    grid = (lo..hi).step(10).map do |v|
      tag.line(x1: pad_l, x2: width - pad_r, y1: y.(v), y2: y.(v), class: "grid") +
        tag.text(v, x: pad_l - 6, y: y.(v) + 4, class: "axis", "text-anchor": "end")
    end

    zone = recommendation.pool.zone
    day_marks = rows.each_with_index.filter_map do |r, i|
      local = Time.zone.parse(r["t"]).in_time_zone(zone)
      next unless local.hour.zero?

      tag.line(x1: x.(times[i]), x2: x.(times[i]), y1: pad_t, y2: height - pad_b, class: "grid") +
        tag.text(local.strftime("%a"), x: x.(times[i]) + 3, y: height - 8, class: "axis")
    end

    lines = SERIES.select { |s| keys.include?(s[:key]) }.map do |s|
      points = rows.each_with_index.map { |r, i| "#{x.(times[i]).round(1)},#{y.(r[s[:key]].to_f).round(1)}" }
      tag.polyline(points: points.join(" "), class: "line #{s[:css]}")
    end

    svg = tag.svg(safe_join(grid + day_marks + lines), viewBox: "0 0 #{width} #{height}", class: "chart",
                  role: "img", "aria-label": "Forecast and pool temperature plan")
    legend = tag.div(class: "legend") do
      safe_join(SERIES.select { |s| keys.include?(s[:key]) }.map { |s| tag.span(s[:label], class: "key #{s[:css]}") })
    end
    tag.div(svg + legend, class: "chart-wrap")
  end
end
