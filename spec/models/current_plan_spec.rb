require "rails_helper"

RSpec.describe CurrentPlan do
  let(:pool) { create(:pool) }

  it "makes a plan when there is none" do
    expect(described_class.for(pool).recommendation).to be_persisted
  end

  it "reuses a plan that's still current" do
    first = described_class.for(pool).recommendation
    expect(described_class.for(pool).recommendation).to eq(first)
  end

  it "re-plans after a settings change, a deploy, or an hour" do
    first = described_class.for(pool).recommendation
    travel(1.minute) { pool.update!(warm_day_threshold: 40) }
    travel(2.minutes) { expect(described_class.for(pool).recommendation).not_to eq(first) }
  end

  it "keeps the old plan and reports the error when the forecast fails" do
    first = described_class.for(pool).recommendation
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    travel 2.hours do
      plan = described_class.for(pool)
      expect(plan.recommendation).to eq(first)
      expect(plan.error).to include("down")
    end
  end
end
