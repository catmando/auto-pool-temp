require "rails_helper"

RSpec.describe PoolCheckJob do
  include ActiveJob::TestHelper

  it "runs a notifying check" do
    pool = create(:pool)
    described_class.perform_now(pool)
    expect(pool.recommendations.count).to eq(1)
    expect(Sms.sender.deliveries.size).to eq(1)
  end

  it "retries when the weather service fails" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    pool = create(:pool)
    expect { described_class.perform_now(pool) }.to have_enqueued_job(described_class)
  end
end
