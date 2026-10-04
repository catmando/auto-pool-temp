# Behavior every schedule planner must have.
RSpec.shared_examples "a schedule planner" do
  let(:curve) { TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102) }
  let(:now) { Time.utc(2026, 10, 1, 4) }
  # Checks at 7am and 5pm UTC.
  let(:checks) { (0..17).flat_map { |d| [ 7, 17 ].map { |h| Time.utc(2026, 10, 1, h) + d.days } }.select { |t| t > now } }

  def plan(forecast, water: nil, heat: 3 / 24.0, cool: 2 / 24.0, warm_threshold: 80)
    described_class.new(forecast: forecast, curve: curve, heat_rate: heat, cool_rate: cool, now: now,
                        check_times: checks.select { |t| t <= forecast.end_time }, water_temp: water,
                        warm_threshold: warm_threshold).call
  end

  it "recommends the ideal in steady weather" do
    result = plan(flat_forecast(65, start: now))
    expect(result.target).to eq(91)
    expect(result.reason).to include("ideal is about 91°F")
  end

  it "only changes the setting at check times" do
    rows = plan(hourly_forecast(start: now) { |h| h < 100 ? 70 : 50 }).details[:series]
    changes = rows.each_cons(2).select { |a, b| a[:setpoint] != b[:setpoint] }.map { |_, b| Time.zone.parse(b[:t]) }
    expect(changes).to all(satisfy { |t| [ 7, 17 ].include?(t.hour) })
  end

  it "simulates water that changes no faster than the pool can" do
    rows = plan(hourly_forecast(start: now) { |h| h < 72 ? 75 : 45 }, water: 85).details[:series]
    rows.each_cons(2) do |a, b|
      expect(b[:pool] - a[:pool]).to be <= 3 / 24.0 + 0.011 # rows round to 0.01°F
      expect(a[:pool] - b[:pool]).to be <= 2 / 24.0 + 0.011
    end
  end

  it "starts from the water temperature it's given" do
    result = plan(flat_forecast(65, start: now), water: 84)
    expect(result.details[:water_now]).to eq(84)
    expect(result.reason).to include("heat it up from about 84°F")
    expect(result.target).to be > 84
  end

  it "returns a schedule and comfort score" do
    details = plan(flat_forecast(65, start: now)).details
    expect(details[:schedule].first).to include(:t, :setpoint)
    expect(details[:comfort]).to include(:mean_discomfort, :worst_discomfort, :comfortable_share)
  end
end
