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
