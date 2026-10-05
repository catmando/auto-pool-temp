require "rails_helper"

RSpec.describe RefreshPlansJob do
  it "re-plans each pool and tells its open dashboards to refresh" do
    pool = create(:pool)
    create(:pool, :unlocated)
    expect(Turbo::StreamsChannel).to receive(:broadcast_refresh_to).with(pool).once
    expect { described_class.perform_now }.to change(pool.recommendations, :count).by(1)
  end

  it "doesn't re-plan a plan that's still current, but still refreshes" do
    pool = create(:pool)
    CurrentPlan.for(pool)
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_to)
    expect { described_class.perform_now }.not_to change(pool.recommendations, :count)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to).with(pool)
  end

  it "runs hourly in production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"))
    expect(recurring.dig("production", "refresh_plans")).to include("class" => "RefreshPlansJob", "schedule" => "every hour at minute 2")
  end
end
