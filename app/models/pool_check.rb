# One full check of a pool: fetch the forecast, run the pool's recommender,
# record the result, and text the user if the heater setting should change.
class PoolCheck
  attr_reader :pool, :now, :recommendation, :text_message

  def self.call(pool, **options) = new(pool, **options).call

  def initialize(pool, notify: true, now: Time.current, weather: Weather.provider, sender: nil)
    @pool = pool
    @notify = notify
    @now = now
    @weather = weather
    @sender = sender
  end

  # In test mode the saved forecast is used, "now" is when it was saved, and
  # nothing is ever sent.
  def call
    snapshot = pool.test_snapshot
    raise ArgumentError, "#{pool.name} has no location set" unless snapshot || pool.located?

    result =
      if snapshot
        pool.recommender_class.for_pool(pool, forecast: snapshot.forecast, now: snapshot.taken_at,
                                              water_temp: snapshot.water_temp).call
      else
        forecast = @weather.forecast(latitude: pool.latitude, longitude: pool.longitude, days: Pool::FORECAST_DAYS)
        adopt_time_zone(forecast.time_zone)
        pool.recommender_class.for_pool(pool, forecast: forecast, now: now).call
      end
    previous = pool.assumed_setpoint
    cover_change = cover_change(result)
    pump_change = pump_change(result)
    change = pool.needs_change?(result.target) || !cover_change.nil? || !pump_change.nil?

    details = result.details.merge(test_snapshot_id: snapshot&.id, test_snapshot_name: snapshot&.name)
    @recommendation = pool.recommendations.create!(
      strategy: pool.strategy, target_temp: result.target, raw_target: result.raw_target,
      assumed_setpoint: previous, reason: result.reason, details: details)

    if @notify && !snapshot && change && pool.notifiable?
      @text_message = TextMessage.deliver(pool: pool, body: self.class.message_for(pool, result, previous), sender: @sender)
      unless @text_message.failed?
        @recommendation.update!(notified: true)
        pool.record_setpoint!(result.target, source: "recommended", at: now)
        pool.record_cover!(cover_change, at: now) unless cover_change.nil?
        pool.record_pump_extended!(pump_change, at: now) unless pump_change.nil?
      end
    end

    pool.update!(last_checked_at: now) if @notify && !snapshot
    self
  end

  def notified? = recommendation&.notified?

  def self.message_for(pool, result, previous)
    assumption =
      if previous
        "I'm assuming it's set to #{previous}°F now. If not, reply with the actual setting (e.g. \"84\")."
      else
        "I don't know its current setting, so reply with it (e.g. \"84\") if it's different."
      end
    [ "#{pool.name}: set the heater to #{result.target}°F#{cover_instruction(pool, result)}#{pump_instruction(pool, result)}.",
      result.reason,
      upcoming_changes(pool, result), assumption ]
      .compact.join(" ")
  end

  # "Coming up: Tue 7am 96°F, Wed 5pm 93°F." from the plan, if it has one.
  # ", and run the pump around the clock" / ", and put the pump back on its normal schedule".
  def self.pump_instruction(pool, result)
    wanted = result.details[:pump_extra]
    return "" if wanted.nil? || wanted == pool.pump_extended?

    wanted ? ", and run the pump around the clock until it warms up" : ", and put the pump back on its normal schedule"
  end

  # ", and take the cover off" / ", and put the cover back on" when that should change.
  def self.cover_instruction(pool, result)
    wanted = result.details[:cover_on]
    return "" if wanted.nil? || wanted == pool.cover_on?

    wanted ? ", and put the cover back on" : ", and take the cover off"
  end

  def self.upcoming_changes(pool, result, limit: 3)
    schedule = Array(result.details[:schedule])
    changes = schedule.each_cons(2).filter_map { |a, b| b if b[:setpoint] != a[:setpoint] }.first(limit)
    return if changes.empty?

    "Coming up: " + changes.map { |c| "#{Time.zone.parse(c[:t].to_s).in_time_zone(pool.zone).strftime('%a %-l%P')} #{c[:setpoint]}°F" }.join(", ") + "."
  end

  private

  # Pump around the clock (true) or on schedule (false), if that should change now (nil otherwise).
  def pump_change(result)
    wanted = result.details[:pump_extra]
    wanted unless wanted.nil? || wanted == pool.pump_extended?
  end

  # The cover state the plan wants now, if that's different from now (nil otherwise).
  def cover_change(result)
    wanted = result.details[:cover_on]
    wanted unless wanted.nil? || wanted == pool.cover_on?
  end

  def adopt_time_zone(name)
    return if name.blank? || name == pool.time_zone || ActiveSupport::TimeZone[name].nil?

    pool.update!(time_zone: name)
  end
end
