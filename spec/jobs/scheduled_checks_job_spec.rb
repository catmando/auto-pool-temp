require "rails_helper"

RSpec.describe ScheduledChecksJob do
  include ActiveJob::TestHelper

  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }

  it "enqueues checks only for pools that are due" do
    due = create(:pool, last_checked_at: zone.local(2026, 10, 1, 7, 5))
    other = create(:pool, checks_per_day: 3, last_checked_at: zone.local(2026, 10, 1, 13, 5))
    create(:pool, :unlocated)

    expect { described_class.perform_now(zone.local(2026, 10, 1, 17, 5)) }
      .to have_enqueued_job(PoolCheckJob).with(due).exactly(:once)
    expect(PoolCheckJob).not_to have_been_enqueued.with(other)
  end
end
