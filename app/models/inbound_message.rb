# Handles a message the user sends back, on any channel. A reply to an alert
# means "done": the heater was set as advised, at the time of the reply.
#   "/start <token>"           -> (Telegram) link this chat to a pool
#   "123456"                   -> (SMS) phone confirmation code
#   "86" / "86F" / "done 86"   -> done, and the water is 86°F now (logged)
#   "done" / "ok" / "yes"      -> done (logged)
#   "water 86"                 -> just a water reading (logged)
#   "heater 84" / "set 84"     -> the heater is actually at 84°F; re-check and advise
#   "cover on" / "cover off"   -> the pool cover is now on / off
#   "pump on" / "pump normal"  -> the pump is running around the clock / back on its schedule
#   "help" / "info"            -> the program description carriers require (SmsProgram::HELP)
#   "status" / "?"             -> what the heater should be set to now
#   "pause" / "resume"         -> turn alerts off / on (Twilio also handles STOP itself)
#   anything else              -> help
# Replies go back on the same channel, to the sender.
class InboundMessage
  HELP = "Reply with the pool's current temperature (e.g. \"86\") once the heater is set, or DONE. " \
         "Also: HEATER 84 if the heater is set differently, STATUS for the current advice, PAUSE / RESUME for alerts."

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
    when /\Apump\s+(normal|schedule|on|always|24\/7)\z/
      extended = $1 != "normal" && $1 != "schedule"
      pool.record_pump_extended!(extended, at: @now)
      extended ? "Got it, the pump is running around the clock." : "Got it, the pump is back on its normal schedule."
    when /\Acover\s+(on|off)\z/, /\A(?:\/)?cover(on|off)\z/
      pool.record_cover!($1 == "on", at: @now)
      "Got it, the cover is #{$1}."
    when /\A(?:water|pool|w)\s*(?:is|at|=|:)?\s*(\d{2,3}(?:\.\d+)?)\s*°?\s*f?\z/
      water_reported($1.to_f, pool)
    when /\A(?:(?:done|ok|okay|yes|y|👍)[\s,.!]*)?(?:(?:water|pool|w)\s*(?:is|at|=|:)?\s*)?(\d{2,3}(?:\.\d+)?)\s*°?\s*f?\z/,
         /\A(?:done|ok|okay|yes|y|👍)[\s,.!]*\z/
      confirmed($1&.to_f, pool)
    when /\A(?:heater|set)\s*(?:is|at|to|=|:)?\s*(\d{2,3})\s*°?\s*f?\z/
      reported($1.to_i, pool)
    when "help", "info", "/help"
      SmsProgram::HELP
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

  # Logged with what the model expected; not used by the planner yet.
  def water_reported(value, pool)
    return "#{value.round}°F doesn't look like a water temperature. #{HELP}" unless (32..110).cover?(value)

    log = PoolLog.water_reading!(pool, value, source: @channel, at: @now)
    "Thanks, logged the water at #{fmt_degrees(value)}°F#{expected_note(log)}."
  end

  # "Done": the heater was set as the last alert said, now. Logged, with a reading if given.
  def confirmed(value, pool)
    return "#{value.round}°F doesn't look like a water temperature. #{HELP}" if value && !(32..110).cover?(value)

    log = PoolLog.confirm_setting!(pool, water_temp: value, source: @channel, at: @now)
    setting = pool.assumed_setpoint ? "the heater at #{pool.assumed_setpoint}°F" : "your change"
    water = value ? " and the water at #{fmt_degrees(value)}°F#{expected_note(log)}" : ""
    "Thanks, logged #{setting}#{water}."
  end

  def expected_note(log)
    log.expected_water_temp ? " (I expected about #{log.expected_water_temp.round}°F)" : ""
  end

  def fmt_degrees(value) = (value % 1).zero? ? value.to_i.to_s : value.round(1).to_s

  def status(pool)
    check = PoolCheck.call(pool, notify: false, now: @now, weather: @weather)
    setting = pool.assumed_setpoint ? "#{pool.assumed_setpoint}°F" : "unknown"
    "Target now: #{check.recommendation.target_temp}°F (I think it's set to #{setting}). #{check.recommendation.reason}"
  end
end
