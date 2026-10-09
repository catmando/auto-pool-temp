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

  ASK_FOR_TEMP = "Respond with current pool temperature to improve system accuracy.".freeze

  # The alert, short and to the point:
  #   Colder weather coming.                      (why, if there's a reason to give; see headline)
  #   Your heater should be set to: 94°F
  #   Leave the pump running 24 hours for now.    (only when that's part of the advice)
  #   Cover should be on when not in use.         (pools with a cover)
  #   Respond with current pool temperature to improve system accuracy.
  def self.message_for(pool, result, _previous = nil)
    [ headline(pool, result),
      "Your heater should be set to: #{result.target}°F",
      pump_line(pool, result),
      cover_line(pool, result),
      ASK_FOR_TEMP ].compact.join("\n")
  end

  PARTY_HEADS_UP = 48 # hours

  # Why the setting is changing (owner's rules, 2026-10-09):
  #   - a pool party on now or within 2 days, unless the plan is cooling: "Get ready for your pool party."
  #   - heating the water because colder weather is coming: "Colder weather coming."
  #   - cooling it because warmer weather is coming: "Warmer weather coming."
  # A weather line only appears when a coming day's average air is >5°F off today's (WeatherTrend)
  # in the direction that explains the change; otherwise there's no headline.
  def self.headline(pool, result)
    rows = Array(result.details[:series]).map { |r| r.to_h.transform_keys(&:to_sym) }
    water = result.details[:water_now]&.to_f
    heating = water && result.target > water + 0.5
    cooling = water && result.target < water - 0.5
    return "Get ready for your pool party." if !cooling && rows.first(PARTY_HEADS_UP).any? { |r| r[:party].to_s == "party" }

    trend = WeatherTrend.for(rows, zone: pool.zone)
    if heating && trend == :cooler then "Colder weather coming."
    elsif cooling && trend == :warmer then "Warmer weather coming."
    end
  end

  def self.pump_line(pool, result)
    wanted = result.details[:pump_extra]
    if wanted then "Leave the pump running 24 hours for now."
    elsif wanted == false && pool.pump_extended? then "Put the pump back on its normal schedule."
    end
  end

  def self.cover_line(pool, result)
    return unless pool.has_cover?

    result.details[:cover_on] == false ? "Remove the cover for rapid cooling." : "Cover should be on when not in use."
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
