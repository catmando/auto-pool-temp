require "rails_helper"
require_relative "shared_examples"

RSpec.describe Recommenders::Linear do
  it_behaves_like "a recommender"

  it "ignores upcoming changes" do
    now = Time.utc(2026, 10, 1, 12)
    curve = TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102)
    forecast = step_forecast(before: 65, after: 35, at_hour: 30, start: now)
    result = described_class.new(forecast: forecast, curve: curve, heat_rate: 3, cool_rate: 2, now: now).call
    expect(result.target).to eq(91)
  end
end
