require "rails_helper"

RSpec.describe TargetCurve do
  subject(:curve) { described_class.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102) }

  it "hits both anchor points" do
    expect(curve.pool_temp_for(95)).to eq(80)
    expect(curve.pool_temp_for(35)).to eq(102)
  end

  it "is linear between them" do
    expect(curve.pool_temp_for(65)).to be_within(0.001).of(91)
    expect(curve.slope).to be_within(0.0001).of(-11.0 / 30)
  end

  it "keeps extrapolating past the anchors" do
    expect(curve.pool_temp_for(105)).to be_within(0.01).of(76.33)
    expect(curve.base_pool_temp_for(20)).to be_within(0.01).of(107.5)
  end

  it "never aims above 104°F" do
    expect(curve.pool_temp_for(20)).to eq(104)
    expect(curve.pool_temp_for(35, adjustment: 10)).to eq(104)
  end

  it "shifts by the comfort adjustment" do
    warmer = described_class.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102, adjustment: 3)
    expect(warmer.pool_temp_for(65)).to be_within(0.001).of(94)
    expect(warmer.pool_temp_for(65, adjustment: -2)).to be_within(0.001).of(89)
    expect(warmer.base_pool_temp_for(65)).to be_within(0.001).of(91)
  end

  it "rejects identical air anchors" do
    expect { described_class.new(hot_air: 50, hot_pool: 80, cold_air: 50, cold_pool: 90) }.to raise_error(ArgumentError)
  end

  it "builds from a pool's settings, including the comfort adjustment" do
    pool = build(:pool, hot_air_temp: 90, hot_pool_temp: 82, cold_air_temp: 40, cold_pool_temp: 100, comfort_adjustment: -2)
    expect(described_class.for(pool).pool_temp_for(90)).to eq(80)
  end

  it "defaults new pools to 95°F air -> 75°F pool and 35°F air -> 98°F pool" do
    curve = described_class.for(create(:user).pool)
    expect(curve.pool_temp_for(95)).to eq(75)
    expect(curve.pool_temp_for(35)).to eq(98)
  end
end
