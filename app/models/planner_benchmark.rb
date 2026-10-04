# A fixed set of weather scenarios for measuring how well a planner keeps the
# expected water near the ideal. Nothing here changes over time: the forecasts
# are committed fixtures or made-up patterns on fixed dates, and the pool
# settings are fixed. spec/models/planner_benchmark_spec.rb fails if a change
# makes any scenario's error worse than the recorded baseline.
#
#   bin/rails planner:benchmark          # show the current scores vs the baseline
#   bin/rails planner:record_baseline    # accept the current scores as the new baseline
class PlannerBenchmark
  BASELINE_PATH = Rails.root.join("spec/fixtures/planner_baseline.yml")
  FORECASTS_DIR = Rails.root.join("spec/fixtures/forecasts")
  # Made-up patterns start at midnight on this day, Rochester time.
  PATTERN_START = ActiveSupport::TimeZone["America/New_York"].local(2026, 10, 5)
  # Scores may wobble this much (°F) from float rounding without counting as worse.
  TOLERANCE = 0.005

  Scenario = Data.define(:key, :forecast, :now, :water_temp)

  # The owner's settings as of 2026-10-05 (pump 4-10am and 4-10pm; heats 2°F/h, cools 0.1°F/h).
  def self.pool
    Pool.new(hot_air_temp: 95, hot_pool_temp: 80, cold_air_temp: 35, cold_pool_temp: 102,
             heat_rate_per_hour: 2, cool_rate_per_hour: 0.1, checks_per_day: 2, warm_day_threshold: 80,
             pump_on_1: "04:00", pump_off_1: "10:00", pump_on_2: "16:00", pump_off_2: "22:00",
             time_zone: "America/New_York")
  end

  def scenarios
    @scenarios ||= saved_forecasts + PlannerLab::PATTERNS.map do |key, pattern|
      Scenario.new(key, PlannerLab.pattern_forecast(pattern, start: PATTERN_START, time_zone: "America/New_York"),
                   PATTERN_START, nil)
    end
  end

  # { scenario_key => { mean_error:, mean_discomfort: } } for one planner.
  def scores(strategy = "search")
    pool = self.class.pool
    klass = Recommenders.for(strategy)
    scenarios.to_h do |s|
      result = klass.new(forecast: s.forecast, curve: TargetCurve.for(pool), heat_rate: pool.heat_rate_per_hour,
                         cool_rate: pool.cool_rate_per_hour, pump: pool.pump_schedule, now: s.now, water_temp: s.water_temp,
                         check_times: pool.check_times_between(s.now, s.forecast.end_time),
                         warm_threshold: pool.warm_day_threshold).call
      comfort = result.details[:comfort]
      [ s.key, { "mean_error" => comfort[:mean_error], "mean_discomfort" => comfort[:mean_discomfort] } ]
    end
  end

  def baseline = File.exist?(BASELINE_PATH) ? YAML.load_file(BASELINE_PATH) : {}

  # Every planner's scores, so other planners can be compared to the default.
  def all_scores = Recommenders.keys.to_h { |key| [ key, scores(key) ] }

  def record_baseline!
    File.write(BASELINE_PATH, <<~YAML + all_scores.to_yaml.delete_prefix("---\n"))
      # Planner error per benchmark scenario (°F). Lower is better.
      #   mean_error:      average |expected water - ideal|
      #   mean_discomfort: the same, with the comfortable direction counting less
      # Checked by spec/models/planner_benchmark_spec.rb; update with `bin/rails planner:record_baseline`.
    YAML
  end

  private

  def saved_forecasts
    Dir[FORECASTS_DIR.join("*.json")].sort.map do |path|
      data = JSON.parse(File.read(path))
      forecast = Weather::Forecast.new(
        data["points"].map { |epoch, temp| Weather::Forecast::Point.new(Time.zone.at(epoch), temp.to_f) },
        time_zone: data["time_zone"], source: "fixture")
      Scenario.new(File.basename(path, ".json"), forecast, Time.zone.parse(data["taken_at"]), data["water_temp"])
    end
  end
end
