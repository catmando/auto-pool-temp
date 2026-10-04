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
      expect(row_at(result, 108)[:pool]).to be >= row_at(result, 84)[:pool] - 0.5 # settings are whole degrees
    end

    it "explains a head start" do
      result = plan(hourly_forecast(start: now) { |h| (40...100).cover?(h) ? 40 : 65 })
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
