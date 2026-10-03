require "rails_helper"

RSpec.describe Recommendation do
  it { is_expected.to belong_to(:pool) }
  it { is_expected.to validate_presence_of(:strategy) }
  it { is_expected.to validate_presence_of(:target_temp) }

  it "exposes the stored series" do
    expect(build(:recommendation).series.first).to include("desired" => 88)
    expect(build(:recommendation, details: nil).series).to eq([])
  end

  it "orders recent first" do
    pool = create(:pool)
    old = create(:recommendation, pool: pool, created_at: 2.days.ago)
    newer = create(:recommendation, pool: pool)
    expect(pool.recommendations.recent).to eq([ newer, old ])
  end
end
