require "rails_helper"

# "Leave the pump on": when the normal pump hours can't keep up with the weather
# (or a party), recommend running the pump (and heater) around the clock, but only
# when the water would otherwise fall more than pump_boost_threshold short.
RSpec.describe Recommenders::Search, "running the pump around the clock" do
  let(:zone) { ActiveSupport::TimeZone["America/New_York"] }
  let(:now) { zone.local(2026, 10, 5, 8) }
  # A slow heater with a short pump window: it can't keep up with a cold snap.
  let(:slow_pool) do
    build(:pool, heat_rate_per_hour: 0.3, has_cover: true, time_zone: zone.name, pump_on_1: "06:00", pump_off_1: "10:00",
                 pump_on_2: "", pump_off_2: "", pump_boost_threshold: 3)
  end
  let(:cold_snap) { hourly_forecast(start: now, time_zone: zone.name) { |h| (24...96).cover?(h) ? 35 : 65 } }

  def plan(pool, forecast = cold_snap, water: 91, parties: [])
    described_class.new(forecast: forecast, now: now, water_temp: water,
                        check_times: pool.check_times_between(now, forecast.end_time),
                        **Recommenders::Base.pool_options(pool).merge(parties: parties)).call
  end

  def extra_flags(result) = result.details[:schedule].map { |s| s[:pump_extra] }

  # The threshold is when to recommend it (the owner's rule), not a guarantee: once the
  # weather alone no longer calls for it, the pump goes back to normal hours.
  it "runs the pump around the clock when the normal hours can't keep up, cutting the shortfall" do
    worst = ->(result) { result.details[:series].map { |r| r[:desired] - r[:pool] }.max }
    result = plan(slow_pool)
    never = plan(slow_pool.dup.tap { |p| p.pump_boost_threshold = 20 })
    expect(extra_flags(result)).to include(true)
    expect(extra_flags(never)).to all(be false)
    expect(worst.(result)).to be < worst.(never) - 3
  end

  it "runs it in one stretch, then goes back to normal (no switching back and forth)" do
    flags = extra_flags(plan(slow_pool))
    expect(flags.chunk_while { |a, b| a == b }.map(&:first)).to eq([ true, false ]).or eq([ false, true, false ])
  end

  it "waits for a bigger shortfall with a higher threshold" do
    eager = extra_flags(plan(slow_pool)).index(true)
    patient = extra_flags(plan(slow_pool.dup.tap { |p| p.pump_boost_threshold = 10 })).index(true)
    expect(patient).to be > eager
  end

  it "never runs it for a pool whose normal pump hours keep up" do
    fast = build(:pool, heat_rate_per_hour: 2, has_cover: true, time_zone: zone.name)
    expect(extra_flags(plan(fast))).to all(be false)
  end

  it "can be triggered by a pool party" do
    mild = flat_forecast(65, start: now, time_zone: zone.name)
    party = PoolParty::Window.new(zone.local(2026, 10, 6, 12), zone.local(2026, 10, 6, 23, 59), 10)
    expect(extra_flags(plan(slow_pool, mild))).to all(be false)
    expect(extra_flags(plan(slow_pool, mild, parties: [ party ]))).to include(true)
  end

  it "says so in the reason" do
    expect(plan(slow_pool, water: 85).reason).to include("run the pump around the clock")
  end
end
