# Handles a message the user sends back, on any channel. Supported:
#   "/start <token>"         -> (Telegram) link this chat to a pool
#   "123456"                 -> (SMS) phone confirmation code
#   "84" / "84F" / "set 84"  -> heater is actually at 84°F; re-check and advise
#   "water 86" / "w 86"      -> the water itself is 86°F; re-plan from there
#   "cover on" / "cover off" -> the pool cover is now on / off
#   "status" / "?"           -> what the heater should be set to now
#   "pause" / "resume"       -> turn alerts off / on (Twilio also handles STOP itself)
#   anything else            -> help
# Replies go back on the same channel, to the sender.
class InboundMessage
  HELP = "Reply with your heater's current setting (e.g. \"84\"), the water temperature (e.g. \"water 86\"), STATUS for the current recommendation, " \
         "or PAUSE / RESUME to turn alerts off or on."

  def self.handle(**options) = new(**options).handle

  def initialize(channel:, from:, body:, sender: nil, weather: Weather.provider, now: Time.current)
    @channel = channel.to_s
    @from = from.to_s
    @body = body.to_s.strip
    @sender = sender
    @weather = weather
    @now = now
  end

  def handle
    if @channel == "telegram" && (match = @body.match(%r{\A/start(?:\s+(\S+))?\z}))
      return link_telegram(match[1])
    end

    pool = find_pool
    log_inbound(pool)
    return :unknown_sender unless pool

    respond(pool, reply_for(pool))
  end

  private

  def find_pool
    case @channel
    when "sms" then Pool.find_by(phone_number: Pool.normalize_value_for(:phone_number, @from))
    when "telegram" then Pool.find_by(telegram_chat_id: @from)
    end
  end

  def log_inbound(pool)
    TextMessage.create!(pool: pool, channel: @channel, direction: "inbound", from: @from,
                        body: @body.presence || "(empty)", status: "received")
  end

  def respond(pool, reply)
    TextMessage.deliver(pool: pool, channel: @channel, to: @from, body: reply, sender: @sender)
    reply
  end

  def link_telegram(token)
    pool = TelegramLink.complete(token, chat_id: @from, now: @now)
    log_inbound(pool)
    if pool
      respond(pool, "Connected! #{pool.name} alerts will come here. #{HELP}")
    else
      TextMessage.deliver(pool: nil, channel: "telegram", to: @from, sender: @sender,
        body: "This link has expired or was already used. Open Settings in Auto Pool Temp and tap \"Connect Telegram\" again.")
      :unknown_link
    end
  end

  def reply_for(pool)
    if @channel == "sms" && !pool.phone_verified?
      return confirm_phone(pool)
    end

    case @body.downcase
    when /\Acover\s+(on|off)\z/, /\A(?:\/)?cover(on|off)\z/
      pool.record_cover!($1 == "on", at: @now)
      "Got it, the cover is #{$1}."
    when /\A(?:water|pool|w)\s*(?:is|at|=|:)?\s*(\d{2,3}(?:\.\d+)?)\s*°?\s*f?\z/
      water_reported($1.to_f, pool)
    when /\A(?:set\s*(?:to)?\s*)?(\d{2,3})\s*°?\s*f?\z/
      reported($1.to_i, pool)
    when "status", "?", "/status"
      status(pool)
    when "pause", "stop", "/pause"
      pool.update!(notifications_enabled: false)
      "Alerts paused for #{pool.name}. Reply RESUME to turn them back on."
    when "resume", "start", "/resume"
      pool.update!(notifications_enabled: true)
      "Alerts resumed for #{pool.name}."
    else
      HELP
    end
  rescue Weather::OpenMeteo::Error, ArgumentError => e
    "Sorry, I couldn't check the forecast right now (#{e.message})."
  end

  def confirm_phone(pool)
    verification = PhoneVerification.new(pool, now: @now)
    if verification.confirm(@body)
      "Thanks, this number is confirmed. #{pool.name} alerts will come here."
    else
      "#{verification.failure_reason} Confirm this number from Settings in Auto Pool Temp before using other commands."
    end
  end

  def reported(value, pool)
    return "#{value}°F doesn't look like a heater setting. #{HELP}" unless (40..110).cover?(value)

    pool.record_setpoint!(value, source: "user_reported", at: @now)
    check = PoolCheck.call(pool, notify: false, now: @now, weather: @weather)
    target = check.recommendation.target_temp
    if pool.needs_change?(target)
      pool.record_setpoint!(target, source: "recommended", at: @now)
      "Thanks, noted #{value}°F. Please change it to #{target}°F. Why: #{check.recommendation.reason}"
    else
      "Thanks, noted #{value}°F. That's right for now (target #{target}°F)."
    end
  end

  def water_reported(value, pool)
    return "#{value.round}°F doesn't look like a water temperature. #{HELP}" unless (32..110).cover?(value)

    pool.record_water_temp!(value, at: @now)
    check = PoolCheck.call(pool, notify: false, now: @now, weather: @weather)
    target = check.recommendation.target_temp
    if pool.needs_change?(target)
      pool.record_setpoint!(target, source: "recommended", at: @now)
      "Thanks, water is #{fmt_degrees(value)}°F. Set the heater to #{target}°F. #{check.recommendation.reason}"
    else
      "Thanks, water is #{fmt_degrees(value)}°F. The heater setting is fine as is (#{target}°F)."
    end
  end

  def fmt_degrees(value) = (value % 1).zero? ? value.to_i.to_s : value.round(1).to_s

  def status(pool)
    check = PoolCheck.call(pool, notify: false, now: @now, weather: @weather)
    setting = pool.assumed_setpoint ? "#{pool.assumed_setpoint}°F" : "unknown"
    "Target now: #{check.recommendation.target_temp}°F (I think it's set to #{setting}). #{check.recommendation.reason}"
  end
end
