# A saved forecast for test mode. While a pool has a test snapshot, every plan
# uses this forecast and treats taken_at as "now", so results don't drift as
# the weather updates, and no alerts are sent.
class ForecastSnapshot < ApplicationRecord
  belongs_to :pool

  validates :name, :taken_at, :time_zone, :points, presence: true

  scope :recent, -> { order(taken_at: :desc, id: :desc) }

  # Save the live forecast as of now.
  def self.capture!(pool, name: nil, now: Time.current, weather: Weather.provider)
    forecast = weather.forecast(latitude: pool.latitude, longitude: pool.longitude, days: Pool::FORECAST_DAYS)
    create!(pool: pool, name: name.presence || default_name(pool, now), taken_at: now,
            time_zone: forecast.time_zone.presence || pool.time_zone,
            water_temp: pool.estimated_water_temp(now),
            points: forecast.points.map { |p| [ p.time.to_i, p.temp.round(2) ] })
  end

  # Rebuild the forecast a past check used, from its saved hourly air temps.
  def self.from_recommendation!(recommendation, name: nil)
    rows = recommendation.series
    raise ArgumentError, "recommendation has no forecast data" if rows.size < 2

    pool = recommendation.pool
    create!(pool: pool, name: name.presence || default_name(pool, recommendation.created_at),
            taken_at: Time.zone.parse(rows.first["t"]), time_zone: pool.time_zone,
            water_temp: recommendation.details["water_now"] || recommendation.assumed_setpoint,
            points: rows.map { |r| [ Time.zone.parse(r["t"]).to_i, r["air"].to_f ] })
  end

  def self.default_name(pool, time)
    "#{pool.location_name.presence || 'Forecast'}, #{time.in_time_zone(pool.zone).strftime('%a %b %-d %-l%P')}"
  end

  def forecast
    Weather::Forecast.new(points.map { |epoch, temp| Weather::Forecast::Point.new(Time.zone.at(epoch), temp.to_f) },
                          time_zone: time_zone, source: "snapshot")
  end

  def label = "#{name} (#{points.size / 24} days)"
end
