module ApplicationHelper
  def degrees(value)
    value.nil? ? "—" : "#{value.to_f.round}°F"
  end

  def local_time(time, pool = current_pool)
    return "never" if time.nil?

    time.in_time_zone(pool.zone).strftime("%a %b %-d, %-l:%M %P")
  end

  def setpoint_source_label(source)
    { "recommended" => "assumed: you followed the last text",
      "user_reported" => "you reported it" }.fetch(source.to_s, "not yet known")
  end
end
