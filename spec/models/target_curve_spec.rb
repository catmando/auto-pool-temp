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
    expect(curve.pool_temp_for(20)).to be_within(0.01).of(107.5)
  end

  it "rejects identical air anchors" do
    expect { described_class.new(hot_air: 50, hot_pool: 80, cold_air: 50, cold_pool: 90) }.to raise_error(ArgumentError)
  end

  it "builds from a pool's settings" do
    pool = build(:pool, hot_air_temp: 90, hot_pool_temp: 82, cold_air_temp: 40, cold_pool_temp: 100)
    expect(described_class.for(pool).pool_temp_for(90)).to eq(82)
  end
end
