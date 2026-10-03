# One full check of a pool: fetch the forecast, run the pool's recommender,
# record the result, and text the user if the heater setting should change.
class PoolCheck
  attr_reader :pool, :now, :recommendation, :text_message

  def self.call(pool, **options) = new(pool, **options).call

  def initialize(pool, notify: true, now: Time.current, weather: Weather.provider, sender: Sms.sender)
    @pool = pool
    @notify = notify
    @now = now
    @weather = weather
    @sender = sender
  end

  def call
    raise ArgumentError, "#{pool.name} has no location set" unless pool.located?

    forecast = @weather.forecast(latitude: pool.latitude, longitude: pool.longitude, days: pool.forecast_days)
    adopt_time_zone(forecast.time_zone)

    result = pool.recommender_class.for_pool(pool, forecast: forecast, now: now).call
    previous = pool.assumed_setpoint
    change = pool.needs_change?(result.target)

    @recommendation = pool.recommendations.create!(
      strategy: pool.strategy, target_temp: result.target, raw_target: result.raw_target,
      assumed_setpoint: previous, reason: result.reason, details: result.details)

    if @notify && change && pool.notifications_enabled? && pool.phone_number.present?
      @text_message = TextMessage.deliver(pool: pool, body: self.class.message_for(pool, result, previous), sender: @sender)
      unless @text_message.failed?
        @recommendation.update!(notified: true)
        pool.record_setpoint!(result.target, source: "recommended", at: now)
      end
    end

    pool.update!(last_checked_at: now) if @notify
    self
  end

  def notified? = recommendation&.notified?

  def self.message_for(pool, result, previous)
    assumption =
      if previous
        "I'm assuming it's at #{previous}°F now. If it isn't, reply with the actual setting (e.g. \"84\")."
      else
        "I don't know its current setting, so reply with it (e.g. \"84\") if it's different."
      end
    "#{pool.name}: set the heater to #{result.target}°F. #{assumption} Why: #{result.reason}"
  end

  private

  def adopt_time_zone(name)
    return if name.blank? || name == pool.time_zone || ActiveSupport::TimeZone[name].nil?

    pool.update!(time_zone: name)
  end
end
