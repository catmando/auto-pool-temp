# Runs every planner against the live forecast and a few made-up weather
# patterns, using a pool's settings, so planners can be compared side by side
# (the Lab page). Made-up patterns are 16 days of hourly air temps built from
# daily averages plus a daily swing (low ~5am, high ~3pm).
class PlannerLab
  Scenario = Data.define(:key, :title, :description, :forecast)
  Run = Data.define(:strategy, :label, :result)

  DAYS = 16
  SWING = 7.0 # ± °F around the daily average

  PATTERNS = {
    "cold_snap" => {
      title: "Cold snap",
      description: "Mild, then three cold days, then mild again.",
      days: [ 72, 72, 71, 70, 46, 44, 47, 62, 68, 70, 70, 69, 70, 71, 70, 70 ]
    },
    "heat_wave" => {
      title: "Heat wave",
      description: "Mild, then five hot days, then back to normal.",
      days: [ 68, 68, 69, 70, 88, 92, 93, 92, 89, 72, 70, 69, 70, 70, 69, 70 ]
    },
    "choppy" => {
      title: "Choppy fall",
      description: "Big swings from day to day, cooling overall.",
      days: [ 76, 58, 72, 55, 70, 74, 52, 60, 68, 50, 56, 66, 48, 58, 62, 50 ]
    }
  }.freeze

  attr_reader :pool, :now

  def initialize(pool, now: Time.current, weather: Weather.provider)
    @pool = pool
    @now = now
    @weather = weather
  end

  def scenarios
    @scenarios ||= [ live_scenario, *saved_scenarios, *PATTERNS.map { |key, p| made_up(key, p) } ].compact
  end

  def runs(scenario)
    Recommenders.registry.map do |key, klass|
      Run.new(key, klass.label, run(klass, scenario))
    end
  end

  private

  def run(klass, scenario)
    live = scenario.key == "live"
    snapshot = (pool.forecast_snapshots.find(scenario.key.delete_prefix("snapshot-")) if scenario.key.start_with?("snapshot-"))
    start = live ? now : (snapshot ? snapshot.taken_at : scenario.forecast.start_time)
    klass.new(forecast: scenario.forecast, curve: TargetCurve.for(pool),
              heat_rate: pool.heat_rate_per_hour, cool_rate: pool.cool_rate_per_hour, pump: pool.pump_schedule, now: start,
              check_times: pool.check_times_between(start, scenario.forecast.end_time),
              water_temp: live ? pool.estimated_water_temp(now) : snapshot&.water_temp,
              warm_threshold: pool.warm_day_threshold).call
  end

  def live_scenario
    return unless pool.located?

    forecast = @weather.forecast(latitude: pool.latitude, longitude: pool.longitude, days: DAYS)
    Scenario.new("live", "Your forecast", "#{pool.location_name.presence || 'Your location'}, next #{DAYS} days.", forecast)
  rescue Weather::OpenMeteo::Error
    nil
  end

  def saved_scenarios
    pool.forecast_snapshots.recent.map do |s|
      Scenario.new("snapshot-#{s.id}", "Saved: #{s.name}", "A saved forecast (test data).", s.forecast)
    end
  end

  def made_up(key, pattern)
    start = now.in_time_zone(pool.zone).beginning_of_day
    Scenario.new(key, pattern[:title], pattern[:description], self.class.pattern_forecast(pattern, start: start, time_zone: pool.time_zone))
  end

  # 16 days of hourly air temps from a pattern's daily averages, starting at +start+.
  def self.pattern_forecast(pattern, start:, time_zone:)
    means = pattern[:days]
    points = (0...(means.size * 24)).map do |h|
      day = h / 24.0
      # Daily averages are centered at noon; blend between neighbors.
      position = (day - 0.5).clamp(0, means.size - 1)
      lower = position.floor
      upper = [ lower + 1, means.size - 1 ].min
      mean = means[lower] + (means[upper] - means[lower]) * (position - lower)
      swing = SWING * Math.sin(2 * Math::PI * ((h % 24) - 9) / 24.0) # peaks ~3pm, lowest ~3am
      Weather::Forecast::Point.new(start + h.hours, mean + swing)
    end
    Weather::Forecast.new(points, time_zone: time_zone, source: "made-up")
  end
end
