# Handles a text the user sends back. Supported replies:
#   "84" / "84F" / "set 84"  -> heater is actually at 84°F; re-check and advise
#   "status" / "?"           -> what the heater should be set to now
#   "stop" / "start"         -> pause / resume notifications (Twilio also handles STOP itself)
#   anything else            -> help text
class SmsReply
  HELP = "Reply with your heater's current setting (e.g. \"84\"), STATUS for the current recommendation, " \
         "or PAUSE / RESUME to turn alerts off or on."

  def self.handle(from:, body:, **options) = new(from: from, body: body, **options).handle

  def initialize(from:, body:, sender: Sms.sender, weather: Weather.provider, now: Time.current)
    @from = from
    @body = body.to_s.strip
    @sender = sender
    @weather = weather
    @now = now
  end

  def handle
    pool = Pool.find_by(phone_number: Pool.normalize_value_for(:phone_number, @from))
    TextMessage.create!(pool: pool, direction: "inbound", from: @from, body: @body.presence || "(empty)", status: "received")
    return :unknown_sender unless pool

    reply = reply_for(pool)
    TextMessage.deliver(pool: pool, body: reply, sender: @sender)
    reply
  end

  private

  def reply_for(pool)
    case @body.downcase
    when /\A(?:set\s*(?:to)?\s*)?(\d{2,3})\s*°?\s*f?\z/
      reported($1.to_i, pool)
    when "status", "?"
      status(pool)
    when "pause", "stop"
      pool.update!(notifications_enabled: false)
      "Alerts paused for #{pool.name}. Reply RESUME to turn them back on."
    when "resume", "start"
      pool.update!(notifications_enabled: true)
      "Alerts resumed for #{pool.name}."
    else
      HELP
    end
  rescue Weather::OpenMeteo::Error, ArgumentError => e
    "Sorry, I couldn't check the forecast right now (#{e.message})."
  end

  def reported(value, pool)
    return "#{value}°F doesn't look like a heater setting. #{HELP}" unless (40..110).cover?(value)

    pool.record_setpoint!(value, source: "user_reported", at: @now)
    check = PoolCheck.call(pool, notify: false, now: @now, weather: @weather, sender: @sender)
    target = check.recommendation.target_temp
    if pool.needs_change?(target)
      pool.record_setpoint!(target, source: "recommended", at: @now)
      "Thanks, noted #{value}°F. Please change it to #{target}°F. Why: #{check.recommendation.reason}"
    else
      "Thanks, noted #{value}°F. That's right for now (target #{target}°F)."
    end
  end

  def status(pool)
    check = PoolCheck.call(pool, notify: false, now: @now, weather: @weather, sender: @sender)
    setting = pool.assumed_setpoint ? "#{pool.assumed_setpoint}°F" : "unknown"
    "Target now: #{check.recommendation.target_temp}°F (I think it's set to #{setting}). #{check.recommendation.reason}"
  end
end
