module ApplicationHelper
  def degrees(value)
    value.nil? ? "—" : "#{value.to_f.round}°F"
  end

  def local_time(time, pool = current_pool)
    return "never" if time.nil?

    time.in_time_zone(pool.zone).strftime("%a %b %-d, %-l:%M %P")
  end

  def setpoint_source_label(source)
    { "recommended" => "assumed: you followed the last alert",
      "user_reported" => "you reported it" }.fetch(source.to_s, "not yet known")
  end

  def water_source_label(pool)
    return "not known yet. Enter a reading, or it's assumed to match the heater" if pool.water_temp.nil? && pool.assumed_setpoint.nil?
    return "assumed to match the heater setting" if pool.water_temp.nil?

    basis = pool.water_temp_source == "reported" ? "your reading of #{degrees(pool.water_temp)}" : "the last estimate"
    "estimated from #{basis} (#{local_time(pool.water_temp_at, pool)}) and the heater setting"
  end

  # The plan's setting changes (and the first setting), with expected water and ideal at each.
  def plan_changes(recommendation, limit: 8)
    rows = recommendation.series
    return [] unless rows.first&.key?("setpoint")

    rows.each_with_index.filter_map { |row, i|
      next unless i.zero? || row["setpoint"] != rows[i - 1]["setpoint"]

      before = i.zero? ? row : rows[i - 1]
      { time: Time.zone.parse(row["t"]), now: i.zero?, setpoint: row["setpoint"], water: before["pool"], ideal: row["desired"] }
    }.first(limit)
  end

  # Deep link for a pending Telegram connection, or nil.
  def telegram_link_url(pool)
    token = pool.telegram_link_token
    return if token.blank? || pool.telegram_link_sent_at.nil? || pool.telegram_link_sent_at.before?(TelegramLink::TOKEN_TTL.ago)

    sender = TelegramBot.sender
    TelegramLink.url(token, username: sender.username) if sender.respond_to?(:username)
  rescue TelegramBot::Error
    nil
  end
end
