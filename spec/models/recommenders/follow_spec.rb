require "rails_helper"
require_relative "shared_examples"

RSpec.describe Recommenders::Follow do
  it_behaves_like "a schedule planner"

  it "doesn't plan ahead for a cold snap" do
    now = Time.utc(2026, 10, 1, 4)
    curve = TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102)
    forecast = step_forecast(before: 65, after: 35, at_hour: 48, start: now)
    expect(described_class.new(forecast: forecast, curve: curve, heat_rate: 2, now: now).call.target).to eq(91)
  end

  it "takes the cover off only when the water is too warm" do
    now = Time.utc(2026, 10, 1, 4)
    curve = TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102)
    result = described_class.new(forecast: flat_forecast(65, start: now), curve: curve, heat_rate: 2, has_cover: true,
                                 now: now, water_temp: 96).call
    expect(result.details[:cover_on]).to be false
  end
end
