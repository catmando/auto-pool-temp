require "rails_helper"

RSpec.describe Comfort do
  def discomfort(pool, air) = described_class.discomfort(pool: pool, ideal: 90, air: air, warm_threshold: 80)

  it "is zero on target" do
    expect(discomfort(90, 60)).to eq(0)
  end

  it "forgives a slightly warmer pool on a cool day, but not a cooler one" do
    expect(discomfort(92, 60)).to eq(0)
    expect(discomfort(93, 60)).to eq(1)
    expect(discomfort(88, 60)).to eq(2)
  end

  it "forgives a slightly cooler pool on a warm day, but not a warmer one" do
    expect(discomfort(88, 85)).to eq(0)
    expect(discomfort(87, 85)).to eq(1)
    expect(discomfort(92, 85)).to eq(2)
  end

  it "scores a series" do
    rows = [ { pool: 90, desired: 90, smoothed_air: 60 }, { pool: 86, desired: 90, smoothed_air: 60 } ]
    expect(described_class.score(rows, warm_threshold: 80)).to eq(mean_discomfort: 2.0, worst_discomfort: 4.0, comfortable_share: 0.5)
  end
end
