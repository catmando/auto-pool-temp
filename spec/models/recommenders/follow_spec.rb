require "rails_helper"
require_relative "shared_examples"

RSpec.describe Recommenders::Follow do
  it_behaves_like "a schedule planner"

  it "doesn't plan ahead for a cold snap" do
    now = Time.utc(2026, 10, 1, 4)
    curve = TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102)
    forecast = step_forecast(before: 65, after: 35, at_hour: 48, start: now)
    result = described_class.new(forecast: forecast, curve: curve, heat_rate: 3, cool_rate: 2, now: now).call
    expect(result.target).to eq(91)
  end
end
