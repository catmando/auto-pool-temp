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

RSpec.describe Recommenders::Search, "warm-day threshold" do
  # The owner's test: with the water at 95 on the Rochester Oct 4 forecast (cool
  # fall days, ~50-65°F air), the usual 80°F threshold makes every day a "cool
  # day", so the planner leans warm. Dropping the threshold to 40 makes every day
  # a "warm day", so it should lean cool instead.
  let(:scenario) { PlannerBenchmark.new.scenarios.find { |s| s.key == "rochester_2026_10_04" } }
  let(:pool) { PlannerBenchmark.pool }

  def offset(threshold)
    described_class.new(forecast: scenario.forecast, now: scenario.now, water_temp: 95,
                        check_times: pool.check_times_between(scenario.now, scenario.forecast.end_time),
                        **Recommenders::Base.pool_options(pool).merge(warm_threshold: threshold))
                   .call.details[:comfort][:mean_offset]
  end

  it "runs warmer than ideal when it's a cool day (threshold 80)" do
    expect(offset(80)).to be > 0
  end

  it "runs cooler than ideal when it counts as a warm day (threshold 40)" do
    expect(offset(40)).to be < 0
  end
end
