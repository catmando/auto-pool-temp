require "rails_helper"

RSpec.describe "Pool parties" do
  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 91) }
  let(:party_day) { (Time.current.in_time_zone(zone) + 2.days).to_date }

  before { sign_in_as(pool.user) }

  def plan_rows = pool.recommendations.recent.first.series

  it "shows the party section above the plan, with a blank block" do
    get root_path
    expect(response.body.index('id="party"')).to be < response.body.index("<h2>Plan</h2>")
    expect(response.body).to include("Plan the party", "Until", "Until (time)", 'data-controller="parties"')
    expect(response.body).to match(/<input[^>]*value="Plan the party"[^>]*disabled="disabled"/) # until a date is picked
  end

  # The owner's bug (2026-10-05): a planned party has to change the plan the dashboard shows.
  it "changes the dashboard's plan: party hours, a higher target, and water on target at the start" do
    get root_path
    post pool_parties_path, params: { start_date: party_day.iso8601, start_time: "12:00", boost: 6 }
    expect(flash[:notice]).to start_with("Pool party planned for")
    get root_path

    rows = plan_rows
    party_rows = rows.select { |r| r["party"] == "party" }
    expect(party_rows.size).to eq(12) # noon to 11:59 PM
    # Steady 65°F air: the spec curve's ideal is 91°F; the +6 boost is added to it.
    expect(party_rows.first["desired"]).to be_within(0.2).of(97)
    expect(rows.reject { |r| r["party"] }.map { |r| r["desired"] }.uniq).to eq([ 91.0 ])
  end

  it "plans so the water is ready when the party starts" do
    post pool_parties_path, params: { start_date: party_day.iso8601, boost: 8 }
    get root_path
    rows = plan_rows
    start = rows.index { |r| r["party"] == "party" }
    expect(rows[start]["pool"]).to be >= rows[start]["desired"] - 0.6
    expect(response.body).to include("Your pool target is", "when the party starts")
  end

  it "adds the boost to the comfort setting, up to +10 above neutral in total" do
    pool.update!(comfort_adjustment: 3)
    post pool_parties_path, params: { start_date: party_day.iso8601, boost: 7 }
    get root_path
    expect(plan_rows.find { |r| r["party"] == "party" }["desired"]).to be_within(0.2).of(91 + 10)
    expect(plan_rows.reject { |r| r["party"] }.map { |r| r["desired"] }.uniq).to eq([ 94.0 ])
    expect(response.body).to include("+7°F on top of your usual setting")
  end

  it "offers boosts from +1 up to the +10 total, and refuses more" do
    pool.update!(comfort_adjustment: 5)
    get root_path
    expect(response.body).to include("+5°F</option>")
    expect(response.body).not_to include("+6°F</option>")
    post pool_parties_path, params: { start_date: party_day.iso8601, boost: 6 }
    expect(flash[:alert]).to include("must be from +1 to +5")
  end

  it "explains that no party can go warmer when the comfort setting is already +10" do
    pool.update!(comfort_adjustment: 10)
    get root_path
    expect(response.body).to include("the warmest a party can go")
  end

  it "updates a party, and deletes it" do
    post pool_parties_path, params: { start_date: party_day.iso8601, boost: 4 }
    party = pool.pool_parties.first
    patch pool_party_path(party), params: { start_date: party_day.iso8601, end_date: (party_day + 2).iso8601, end_time: "10:00", boost: 7 }
    expect(party.reload).to have_attributes(boost: 7, ends_at: zone.local(party_day.year, party_day.month, party_day.day, 10) + 2.days)
    delete pool_party_path(party)
    expect(pool.pool_parties).to be_empty
  end

  it "rejects a party without a date" do
    post pool_parties_path, params: { start_date: "", boost: 4 }
    expect(flash[:alert]).to include("Pick a date")
  end

  it "won't touch another pool's party" do
    other = create(:pool).pool_parties.build.assign_from_form(start_date: party_day.iso8601, boost: 2).tap(&:save!)
    delete pool_party_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
