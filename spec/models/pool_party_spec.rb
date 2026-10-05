require "rails_helper"

RSpec.describe PoolParty do
  let(:pool) { create(:pool, time_zone: "America/New_York") }
  let(:zone) { ActiveSupport::TimeZone["America/New_York"] }

  def party(**fields) = pool.pool_parties.build.assign_from_form(**fields)

  it "defaults to noon until 11:59 PM on the chosen date" do
    p = party(start_date: "2026-10-07", boost: 5)
    expect(p.starts_at).to eq(zone.local(2026, 10, 7, 12))
    expect(p.ends_at).to eq(zone.local(2026, 10, 7, 23, 59))
    expect(p.label).to eq("Wed Oct 7, 12pm until 11:59pm")
  end

  it "can run several days" do
    p = party(start_date: "2026-10-07", start_time: "15:00", end_date: "2026-10-09", end_time: "18:30", boost: 3)
    expect(p).to be_valid
    expect(p.ends_at).to eq(zone.local(2026, 10, 9, 18, 30))
    expect(p.label).to eq("Wed Oct 7, 3pm until Fri Oct 9, 6:30pm")
  end

  it "needs a date, an end after the start, and a 0..10 boost" do
    expect(party(start_date: "", boost: 5).errors[:base]).to include("Pick a date for the party")
    expect(party(start_date: "2026-10-07", end_date: "2026-10-06", boost: 5)).not_to be_valid
    expect(party(start_date: "2026-10-07", boost: 11)).not_to be_valid
  end

  it "fills the form with local dates and times" do
    p = party(start_date: "2026-10-07", start_time: "14:00", boost: 5)
    expect([ p.start_date, p.start_time, p.end_date, p.end_time ]).to eq([ Date.new(2026, 10, 7), "14:00", Date.new(2026, 10, 7), "23:59" ])
  end

  it "lists upcoming parties in order" do
    later = party(start_date: "2026-10-20", boost: 2).tap(&:save!)
    sooner = party(start_date: "2026-10-10", boost: 2).tap(&:save!)
    travel_to(zone.local(2026, 10, 8)) { expect(pool.pool_parties.upcoming).to eq([ sooner, later ]) }
  end

  it "touches the pool so the plan is redone" do
    expect { party(start_date: "2026-10-07", boost: 5).save! }.to(change { pool.reload.updated_at })
  end
end
