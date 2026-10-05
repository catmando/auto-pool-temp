require "rails_helper"
require_relative "shared_examples"

RSpec.describe Recommenders::Search do
  it_behaves_like "a schedule planner"

  let(:curve) { TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102) }
  let(:now) { Time.utc(2026, 10, 1, 4) }
  let(:pump) { PumpSchedule.new([ %w[04:00 10:00], %w[16:00 22:00] ]) }
  let(:checks) { (0..17).flat_map { |d| [ 7, 17 ].map { |h| Time.utc(2026, 10, 1, h) + d.days } }.select { |t| t > now } }

  def plan(forecast, water: nil, cover: true, klass: described_class)
    klass.new(forecast: forecast, curve: curve, heat_rate: 2, has_cover: cover, pump: pump, now: now,
              check_times: checks.select { |t| t <= forecast.end_time }, water_temp: water).call
  end

  def row_at(result, hours) = result.details[:series].find { |r| Time.zone.parse(r[:t]) == now + hours.hours }

  def comfort(result) = result.details[:comfort][:mean_discomfort]

  describe "a cold snap" do
    # Two cold days (ideal ~100°F) after three mild ones (ideal ~91°F).
    let(:snap) { hourly_forecast(start: now) { |h| (72...120).cover?(h) ? 40 : 65 } }

    it "has the water warm when the cold arrives" do
      result = plan(snap)
      expect(row_at(result, 84)[:pool]).to be >= row_at(result, 84)[:desired] - 1
    end

    it "is more comfortable than just following the ideal" do
      expect(comfort(plan(snap))).to be < comfort(plan(snap, klass: Recommenders::Follow))
    end

    it "doesn't cool off during the snap" do
      result = plan(snap)
      expect(row_at(result, 96)[:pool]).to be >= row_at(result, 84)[:pool] - 0.5
    end

    it "takes the cover off afterward to cool down faster, then puts it back" do
      covers = plan(snap).details[:series].map { |r| r[:cover_on] }
      expect(covers[110..150]).to include(false)
      expect(covers.last(24)).to all(be true)
    end
  end

  describe "a heat wave" do
    let(:wave) { hourly_forecast(start: now) { |h| (96...192).cover?(h) ? 92 : 68 } }

    it "lets the pool cool ahead of the heat, cover off" do
      result = plan(wave)
      expect(row_at(result, 96)[:pool]).to be < row_at(result, 0)[:pool] - 3
      expect(result.details[:series][60..96].map { |r| r[:cover_on] }).to include(false)
    end

    it "does better with a cover to take off than without one" do
      expect(comfort(plan(wave))).to be <= comfort(plan(wave, cover: false))
    end

    it "makes few setting changes" do
      settings = plan(wave).details[:schedule].map { |s| [ s[:setpoint], s[:cover_on] ] }
      expect(settings.each_cons(2).count { |a, b| a != b }).to be <= 6
    end
  end

  it "says to take the cover off when the water needs to cool" do
    result = plan(flat_forecast(65, start: now), water: 97)
    expect(result.details[:cover_on]).to be false
    expect(result.reason).to include("with the cover off so it cools faster")
  end

  it "keeps the current setting when changing wouldn't help noticeably" do
    result = plan(hourly_forecast(start: now) { |h| 65 + 0.2 * Math.sin(h / 7.0) }, water: 91)
    expect(result.details[:schedule].map { |s| s[:setpoint] }.uniq).to eq([ 91 ])
  end

  it "plans 16 days of hourly forecast quickly" do
    forecast = hourly_forecast(start: now, days: 16) { |h| 60 + 15 * Math.sin(h / 30.0) }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    plan(forecast)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
  end
end

RSpec.describe Recommenders::Search, "a hot spell with the warm-day threshold at 40" do
  # The owner's test (2026-10-05): the Rochester Oct 4 forecast with every air
  # temperature 30°F higher (daily averages ~80-95°F), and the warm-day
  # threshold at 40 so every day counts as warm (a cooler pool is the fine
  # direction). The water should sit at or below the ideal, except where even
  # the coolest the pool can possibly be (heater never on, cover off) is still
  # above it: hot air warms the water faster than evaporation can cool it.
  let(:scenario) { PlannerBenchmark.new.scenarios.find { |s| s.key == "rochester_2026_10_04" } }
  let(:pool) { PlannerBenchmark.pool }
  let(:hot) do
    Weather::Forecast.new(scenario.forecast.points.map { |p| Weather::Forecast::Point.new(p.time, p.temp + 30) },
                          time_zone: scenario.forecast.time_zone)
  end
  let(:result) do
    described_class.new(forecast: hot, now: scenario.now, check_times: pool.check_times_between(scenario.now, hot.end_time),
                        **Recommenders::Base.pool_options(pool).merge(warm_threshold: 40)).call
  end
  let(:rows) { result.details[:series] }

  # The coolest possible water, hour by hour: heater never on, cover always off.
  let(:coolest) do
    physics = PoolPhysics.new(heat_rate: 2, pump: pool.pump_schedule, environment: PoolEnvironment.new)
    temp = rows.first[:desired]
    rows.map { |r| temp = physics.step(temp, nil, air: r[:air], cover_on: false) }
  end

  it "keeps the expected water at or below the ideal, or as cool as the pool can get" do
    rows.each_with_index do |row, i|
      expect(row[:pool]).to be <= [ row[:desired], coolest[i] ].max + 0.3, "at #{row[:t]}"
    end
  end

  it "runs cool on average" do
    expect(result.details[:comfort][:mean_offset]).to be <= rows.each_index.sum { |i| [ coolest[i] - rows[i][:desired], 0 ].max } / rows.size + 0.1
  end

  it "never asks the heater for more than the ideal, and takes the cover off" do
    expect(rows.map { |r| r[:setpoint] }.max).to be <= rows.map { |r| r[:desired] }.max.ceil
    expect(rows.count { |r| r[:cover_on] == false }).to be > rows.size / 2
  end
end

RSpec.describe Recommenders::Search, "steadiness" do
  # Regression (2026-10-05): with the pump off part of the day, steady weather made
  # the plan flip-flop (91, 92, 91, ...) at nearly every check: an alert each time.
  # Sweep every start hour, since the pump-off dips depend on the time of day.
  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }
  let(:pool) { build(:pool, has_cover: false, assumed_setpoint: 91) }

  (0..23).each do |hour|
    it "holds one setting in steady weather when planned at #{hour}:30" do
      now = zone.local(2026, 10, 5, hour, 30)
      forecast = flat_forecast(65, start: now.beginning_of_hour, days: 6)
      settings = described_class.new(forecast: forecast, now: now, water_temp: 91,
                                     check_times: pool.check_times_between(now, forecast.end_time),
                                     **Recommenders::Base.pool_options(pool)).call.details[:schedule].map { |s| s[:setpoint] }
      expect(settings.uniq.size).to eq(1), "settings: #{settings.inspect}"
    end
  end
end

RSpec.describe Recommenders::Search, "steadiness with a cover" do
  # Same regression, for a pool with a cover: in steady weather the heater
  # setting, the cover, and the pump all stay put, whatever the start hour.
  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }
  let(:pool) { build(:pool, has_cover: true, cover_on: true, assumed_setpoint: 91) }

  (0..23).step(3).each do |hour|
    it "makes no changes in steady weather when planned at #{hour}:30" do
      now = zone.local(2026, 10, 5, hour, 30)
      forecast = flat_forecast(65, start: now.beginning_of_hour, days: 6)
      decisions = described_class.new(forecast: forecast, now: now, water_temp: 91,
                                      check_times: pool.check_times_between(now, forecast.end_time),
                                      **Recommenders::Base.pool_options(pool)).call.details[:schedule]
                                 .map { |s| s.values_at(:setpoint, :cover_on, :pump_extra) }
      expect(decisions.uniq.size).to eq(1), "decisions: #{decisions.uniq.inspect}"
    end
  end
end
