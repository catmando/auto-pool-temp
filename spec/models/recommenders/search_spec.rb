require "rails_helper"
require_relative "shared_examples"

RSpec.describe Recommenders::Search do
  it_behaves_like "a schedule planner"

  let(:curve) { TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102) }
  let(:now) { Time.utc(2026, 10, 1, 4) }
  let(:checks) { (0..17).flat_map { |d| [ 7, 17 ].map { |h| Time.utc(2026, 10, 1, h) + d.days } }.select { |t| t > now } }

  def plan(forecast, water: nil, heat: 3, cool: 2)
    described_class.new(forecast: forecast, curve: curve, heat_rate: heat, cool_rate: cool, now: now,
                        check_times: checks.select { |t| t <= forecast.end_time }, water_temp: water).call
  end

  def row_at(result, hours) = result.details[:series].find { |r| Time.zone.parse(r[:t]) == now + hours.hours }

  def comfort(result) = result.details[:comfort][:mean_discomfort]

  describe "a cold snap" do
    # Two cold days (ideal ~100°F) after three mild ones (ideal ~91°F).
    let(:snap) { hourly_forecast(start: now) { |h| (72...120).cover?(h) ? 40 : 65 } }

    it "heats ahead so the water is warm when the cold arrives" do
      result = plan(snap)
      expect(row_at(result, 72)[:pool]).to be > 95
    end

    it "is more comfortable than just following the ideal" do
      follow = Recommenders::Follow.new(forecast: snap, curve: curve, heat_rate: 3, cool_rate: 2, now: now,
                                        check_times: checks.select { |t| t <= snap.end_time }).call
      expect(comfort(plan(snap))).to be < comfort(follow)
    end

    it "doesn't cool off during the snap to get ready for the mild days after" do
      result = plan(snap)
      # It may ease off a little in the last hours (a degree at most) rather than stay too warm for days after.
      expect(row_at(result, 108)[:pool]).to be >= row_at(result, 84)[:pool] - 1
    end

    it "explains a head start" do
      result = plan(hourly_forecast(start: now) { |h| (24...100).cover?(h) ? 40 : 65 })
      expect(result.reason).to include("colder weather is coming")
    end
  end

  describe "a heat wave" do
    let(:wave) { hourly_forecast(start: now) { |h| (96...192).cover?(h) ? 92 : 68 } }

    it "lets the pool cool ahead of the heat" do
      result = plan(wave)
      expect(row_at(result, 96)[:pool]).to be < row_at(result, 0)[:pool] - 2
    end

    it "makes one setting change for a long cool-down instead of one per check" do
      result = plan(wave)
      settings = result.details[:schedule].map { |s| s[:setpoint] }
      changes = settings.each_cons(2).count { |a, b| a != b }
      expect(changes).to be <= 6
    end
  end

  it "keeps the current setting when changing wouldn't help noticeably" do
    result = plan(hourly_forecast(start: now) { |h| 65 + 0.2 * Math.sin(h / 7.0) }, water: 91)
    expect(result.details[:schedule].map { |s| s[:setpoint] }.uniq).to eq([ 91 ])
  end

  it "plans 16 days of hourly forecast quickly" do
    forecast = hourly_forecast(start: now, days: 16) { |h| 60 + 15 * Math.sin(h / 30.0) }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    plan(forecast)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
  end
end

RSpec.describe Recommenders::Search, "the Rochester forecast of Oct 4, 2026" do
  # The owner's real case: it held 95 on Friday when the ideal was 94, and stayed
  # around 93 Sun-Mon when the ideal was ~91.5, though it could hit both and still
  # be on target Wednesday. Ideal-pool temps by day, as the curve gave them.
  let(:zone) { ActiveSupport::TimeZone["America/New_York"] }
  let(:now) { zone.local(2026, 10, 7, 7) }
  let(:ideal_by_day) { { 7 => 92.5, 8 => 93.0, 9 => 94.0, 10 => 94.0, 11 => 91.5, 12 => 91.7, 13 => 94.0, 14 => 95.0, 15 => 95.0, 16 => 95.0 } }
  let(:curve) { TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102) }
  let(:forecast) do
    points = (0...(9 * 24)).map do |h|
      t = now + h.hours
      ideal = ideal_by_day.fetch(t.day)
      air = 35 + (ideal - 102) / curve.slope # invert the curve
      Weather::Forecast::Point.new(t, air)
    end
    Weather::Forecast.new(points, time_zone: zone.name)
  end
  let(:result) do
    checks = (0..9).flat_map { |d| [ 7, 17 ].map { |h| zone.local(2026, 10, 7, h) + d.days } }.select { |t| t > now }
    described_class.new(forecast: forecast, curve: curve, heat_rate: 3, cool_rate: 2, now: now,
                        check_times: checks, water_temp: 93).call
  end

  def water_on(day, hour) = result.details[:series].find { |r| Time.zone.parse(r[:t]).in_time_zone(zone).then { |t| t.day == day && t.hour == hour } }[:pool]

  it "holds the ideal on Friday instead of running warm" do
    expect(water_on(9, 15)).to be_within(0.6).of(94)
  end

  it "comes down for Sunday and Monday" do
    expect(water_on(12, 9)).to be <= 92.5
  end

  it "is back on target by Wednesday" do
    expect(water_on(14, 15)).to be_within(1).of(95)
  end
end

RSpec.describe Recommenders::Search, "warm-day threshold" do
  # The owner's test: with the water at 95 on the Rochester Oct 4 forecast (cool
  # fall days, ~50-65°F air), the usual 80°F threshold makes every day a "cool
  # day", so the planner leans warm. Dropping the threshold to 40 makes every day
  # a "warm day", so it should lean cool instead.
  let(:scenario) { PlannerBenchmark.new.scenarios.find { |s| s.key == "rochester_2026_10_04" } }
  let(:pool) { PlannerBenchmark.pool }

  def offset(threshold)
    described_class.new(forecast: scenario.forecast, curve: TargetCurve.for(pool), heat_rate: 3, cool_rate: 2,
                        now: scenario.now, water_temp: 95, warm_threshold: threshold,
                        check_times: pool.check_times_between(scenario.now, scenario.forecast.end_time))
                   .call.details[:comfort][:mean_offset]
  end

  it "runs warmer than ideal when it's a cool day (threshold 80)" do
    expect(offset(80)).to be > 0
  end

  it "runs cooler than ideal when it counts as a warm day (threshold 40)" do
    expect(offset(40)).to be < 0
  end
end
