require "rails_helper"

RSpec.describe PlannerLab do
  let(:pool) { create(:pool) }
  subject(:lab) { described_class.new(pool) }

  it "has the live forecast plus the made-up patterns" do
    expect(lab.scenarios.map(&:key)).to eq(%w[live cold_snap heat_wave choppy])
  end

  it "makes 16 days of hourly weather with a daily swing" do
    forecast = lab.scenarios.find { |s| s.key == "cold_snap" }.forecast
    expect(forecast.points.size).to eq(16 * 24)
    day = forecast.points.first(24).map(&:temp)
    expect(day.max - day.min).to be_within(0.5).of(14)
  end

  it "runs every planner on a scenario" do
    runs = lab.runs(lab.scenarios.last)
    expect(runs.map(&:strategy)).to eq(Recommenders.keys)
    expect(runs.first.result.details[:comfort]).to be_present
  end

  it "skips the live forecast for a pool with no location" do
    expect(described_class.new(create(:pool, :unlocated)).scenarios.map(&:key)).not_to include("live")
  end
end
