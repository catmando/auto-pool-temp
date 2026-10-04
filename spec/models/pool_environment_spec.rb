require "rails_helper"

# The owner's standard heat loss/gain model (2026-10-05).
RSpec.describe PoolEnvironment do
  subject(:env) { described_class.new }

  def rate(water, air, cover) = env.rate_per_day(water: water, air: air, cover_on: cover)

  it "hits the owner's reference points" do
    expect(rate(100, 35, true)).to be_within(0.001).of(-3)   # covered
    expect(rate(100, 35, false)).to be_within(0.001).of(-6)  # uncovered, cold air
    expect(rate(100, 90, false)).to be_within(0.001).of(-2)  # uncovered, hot air (evaporation)
  end

  it "slows to zero as the water nears the air temperature (covered)" do
    expect(rate(70, 70, true)).to eq(0)
    expect(rate(80, 70, true).abs).to be < rate(90, 70, true).abs
  end

  it "warms at 0.3°F/day per degree once the air is warmer than the water" do
    expect(rate(80, 90, true)).to be_within(0.001).of(3)
    expect(rate(85, 90, true)).to be_within(0.001).of(1.5)
  end

  it "always loses some to evaporation with the cover off" do
    expect(rate(80, 80, false)).to be < 0
  end

  it "scales everything by the cooling factor" do
    expect(described_class.new(factor: 2).rate_per_day(water: 100, air: 35, cover_on: true)).to be_within(0.001).of(-6)
  end

  it "gives an hourly rate" do
    expect(env.rate_per_hour(water: 100, air: 35, cover_on: true)).to be_within(0.0001).of(-0.125)
  end
end
