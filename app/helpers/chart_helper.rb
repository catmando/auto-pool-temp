module ChartHelper
  # Lines drawn against the left (pool) axis, plus air on the right axis.
  POOL_SERIES = [
    { key: "desired", label: "Ideal pool", css: "desired" },
    { key: "pool", label: "Expected water", css: "pool" },
    { key: "setpoint", label: "Heater or cover changes", css: "setpoint" }
  ].freeze
  AIR_SERIES = { key: "smoothed_air", label: "Air (24h avg, right axis)", css: "air" }.freeze

  # Chart of a recommendation's plan.
  def forecast_chart(recommendation, **options)
    plan_chart(recommendation.series, zone: recommendation.pool.zone, **options)
  end

  # Inline SVG: heater setting steps (labeled where they change), expected water
  # temperature, ideal pool temperature, and air temperature on a second axis.
  # +rows+: hashes with "t", "desired", "pool", "setpoint", "smoothed_air" (string or symbol keys).
  def plan_chart(rows, zone:, width: 760, height: 300)
    rows = rows.map { |r| r.to_h.transform_keys(&:to_s) }
    return tag.p("No forecast data.", class: "muted") if rows.size < 2

    pad_l, pad_r, pad_t, pad_b = 34, 34, 18, 24
    times = rows.map { |r| Time.zone.parse(r["t"].to_s).to_f }
    pool_keys = POOL_SERIES.map { |s| s[:key] }.select { |k| rows.first.key?(k) }
    pool_values = rows.flat_map { |r| pool_keys.map { |k| r[k].to_f } }
    lo, hi = axis_range(pool_values, step: 5)
    air_values = rows.map { |r| r[AIR_SERIES[:key]].to_f }
    air_lo, air_hi = axis_range(air_values, step: 10)

    plot_w = width - pad_l - pad_r
    plot_h = height - pad_t - pad_b
    x = ->(t) { pad_l + (t - times.first) / (times.last - times.first) * plot_w }
    y = ->(v) { pad_t + (hi - v) / (hi - lo).to_f * plot_h }
    y_air = ->(v) { pad_t + (air_hi - v) / (air_hi - air_lo).to_f * plot_h }

    parts = []
    (lo..hi).step(5).each do |v|
      parts << tag.line(x1: pad_l, x2: width - pad_r, y1: y.(v), y2: y.(v), class: "grid")
      parts << tag.text(v, x: pad_l - 5, y: y.(v) + 4, class: "axis", "text-anchor": "end")
    end
    (air_lo..air_hi).step(10).each do |v|
      parts << tag.text(v, x: width - pad_r + 5, y: y_air.(v) + 4, class: "axis air-axis")
    end

    rows.each_with_index do |r, i|
      local = Time.zone.parse(r["t"].to_s).in_time_zone(zone)
      next unless local.hour.zero?

      parts << tag.line(x1: x.(times[i]), x2: x.(times[i]), y1: pad_t, y2: height - pad_b, class: "grid")
      parts << tag.text(local.strftime("%a"), x: x.(times[i]) + 3, y: height - 8, class: "axis")
    end

    parts.concat(pump_bands(rows, times, x, pad_t, plot_h)) if rows.first.key?("pump")
    parties = party_bands(rows, times, x, pad_t, plot_h)
    parts.concat(parties)

    if rows.first.key?(AIR_SERIES[:key])
      points = rows.each_with_index.map { |r, i| "#{x.(times[i]).round(1)},#{y_air.(r[AIR_SERIES[:key]].to_f).round(1)}" }
      parts << tag.polyline(points: points.join(" "), class: "line air")
    end

    (pool_keys - [ "setpoint" ]).each do |key|
      css = POOL_SERIES.find { |s| s[:key] == key }[:css]
      points = rows.each_with_index.map { |r, i| "#{x.(times[i]).round(1)},#{y.(r[key].to_f).round(1)}" }
      parts << tag.polyline(points: points.join(" "), class: "line #{css}")
    end
    parts.concat(setpoint_markers(rows, times, x, y, zone)) if pool_keys.include?("setpoint")

    svg = tag.svg(safe_join(parts), viewBox: "0 0 #{width} #{height}", class: "chart",
                  role: "img", "aria-label": "Heater plan, expected water temperature, and ideal temperature")
    shown = POOL_SERIES.select { |s| pool_keys.include?(s[:key]) }
    shown += [ AIR_SERIES ] if rows.first.key?(AIR_SERIES[:key])
    shown += [ { label: "Pump on", css: "pump" } ] if rows.first.key?("pump")
    shown += [ { label: "Pool party", css: "party" } ] if parties.any?
    legend = tag.div(class: "legend") { safe_join(shown.map { |s| tag.span(s[:label], class: "key #{s[:css]}") }) }
    tag.div(svg + legend, class: "chart-wrap")
  end

  private

  def axis_range(values, step:)
    lo = (values.min / step).floor * step
    hi = (values.max / step).ceil * step
    hi += step if hi == lo
    [ lo, hi ]
  end

  # Light bands behind the hours the pump (and so the heater) runs.
  def pump_bands(rows, times, x, top, height)
    width = times.size > 1 ? x.(times[1]) - x.(times[0]) : 0
    rows.each_with_index.filter_map do |r, i|
      next unless r["pump"].to_f.positive?

      tag.rect(x: x.(times[i]).round(1), y: top, width: (width * r["pump"].to_f).round(2), height: height, class: "pump-band")
    end
  end

  # Bands behind pool-party hours.
  def party_bands(rows, times, x, top, height)
    width = times.size > 1 ? x.(times[1]) - x.(times[0]) : 0
    rows.each_with_index.filter_map do |r, i|
      next unless r["party"].to_s == "party"

      tag.rect(x: x.(times[i]).round(1), y: top, width: width.round(2), height: height, class: "party-band")
    end
  end

  # A dot on the expected-water line wherever the plan changes something
  # (heater setting or cover), at the moment of the change.
  def setpoint_markers(rows, times, x, y, _zone)
    rows.each_with_index.filter_map do |r, i|
      changed = i.zero? || r["setpoint"] != rows[i - 1]["setpoint"] || r["cover_on"] != rows[i - 1]["cover_on"]
      next unless changed

      water = (i.zero? ? r : rows[i - 1])["pool"].to_f
      tag.circle(cx: x.(times[i]).round(1), cy: y.(water).round(1), r: 4, class: "setpoint-marker")
    end
  end
end
