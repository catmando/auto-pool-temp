RSpec.shared_examples "a recommender" do
  let(:curve) { TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102) }
  let(:now) { Time.utc(2026, 10, 1, 12) }

  def recommend(forecast, heat: 3, cool: 2, next_check_at: nil)
    described_class.new(forecast: forecast, curve: curve, heat_rate: heat, cool_rate: cool,
                        now: now, next_check_at: next_check_at).call
  end

  it "recommends the curve value in steady weather" do
    result = recommend(flat_forecast(65, start: now))
    expect(result.target).to eq(91)
    expect(result.raw_target).to be_within(0.01).of(91)
    expect(result.reason).to include("91°F")
  end

  it "returns a chartable hourly series starting now" do
    series = recommend(flat_forecast(65, start: now)).details[:series]
    expect(series.first).to include(t: now.iso8601, air: 65.0, smoothed_air: 65.0, desired: 91.0)
    expect(series.size).to be > 24 * 9
  end

  it "uses the daily average rather than the afternoon peak" do
    swinging = hourly_forecast(start: now) { |h| 65 + 15 * Math.sin(2 * Math::PI * h / 24) }
    expect(recommend(swinging).target).to be_within(1).of(91)
  end
end
