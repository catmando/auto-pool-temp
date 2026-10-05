require "rails_helper"

RSpec.describe PoolParty do
  # Validation messages for the boost after validating.
  PoolParty.define_method(:errors_on_boost) { valid?; errors[:boost] } unless PoolParty.method_defined?(:errors_on_boost)

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

it "needs a date and an end after the start" do
  expect(party(start_date: "", boost: 5).errors[:base]).to include("Pick a date for the party")
  expect(party(start_date: "2026-10-07", end_date: "2026-10-06", boost: 5)).not_to be_valid
end

describe "boost range: +1 up to +10 above neutral in total" do
  it "is +1..+10 with a neutral comfort setting" do
    expect(described_class.boost_range(pool)).to eq(1..10)
  end

  it "shrinks when the comfort setting is already warm (+5 -> +1..+5)" do
    pool.update!(comfort_adjustment: 5)
    expect(described_class.boost_range(pool)).to eq(1..5)
    expect(party(start_date: "2026-10-07", boost: 6).errors_on_boost).to include("must be from +1 to +5")
  end

  it "grows when the comfort setting is cool (-7 -> +1..+17)" do
    pool.update!(comfort_adjustment: -7)
    expect(described_class.boost_range(pool)).to eq(1..17)
  end

  it "is empty when the comfort setting is already +10" do
    pool.update!(comfort_adjustment: 10)
    expect(described_class.boost_range(pool)).to be_none
    expect(party(start_date: "2026-10-07", boost: 1).errors_on_boost.first).to include("already at +10")
  end

  it "needs at least +1" do
    expect(party(start_date: "2026-10-07", boost: 0)).not_to be_valid
  end
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
