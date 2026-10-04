require "rails_helper"

RSpec.describe "Dashboard" do
  let(:pool) { create(:pool, assumed_setpoint: 88, setpoint_source: "recommended") }

  before { sign_in_as(pool.user) }

  it "sends an unlocated pool to settings" do
    pool.update!(latitude: nil, longitude: nil)
    get root_path
    expect(response).to redirect_to(edit_pool_path)
  end

  it "shows the setting and schedule before any checks" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("88°F", "assumed: you followed the last alert", "No checks yet", "Austin, Texas, US",
                                     "alerts go by Text message (Twilio)", "not configured")
  end

  it "warns when the alert address isn't confirmed" do
    pool.update!(phone_verified_at: nil)
    get root_path
    expect(response.body).to include("not confirmed yet")
  end

  it "shows the latest recommendation, chart, and messages" do
    create(:recommendation, pool: pool, target_temp: 93, reason: "Cold coming.")
    create(:text_message, pool: pool, body: "Set the heater to 93°F.")
    get root_path
    expect(response.body).to include("93°F", "Cold coming.", "<svg", "Set the heater to 93°F.")
  end
end
