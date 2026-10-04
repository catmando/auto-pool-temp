require "rails_helper"

RSpec.describe "Dashboard" do
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 88, setpoint_source: "recommended") }

  before { sign_in_as(pool.user) }

  it "sends an unlocated pool to settings" do
    pool.update!(latitude: nil, longitude: nil)
    get root_path
    expect(response).to redirect_to(edit_pool_path)
  end

  it "shows the setting, water estimate, and schedule before any checks" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("88°F", "assumed: you followed the last alert", "~88°F", "assumed to match the heater",
                                     "No checks yet", "Austin, Texas, US", "alerts go to Telegram")
  end

  it "warns when Telegram isn't connected" do
    pool.update!(telegram_chat_id: nil)
    get root_path
    expect(response.body).to include("not connected yet")
  end

  it "shows the plan chart and a table of upcoming settings" do
    post checks_path, params: { notify: "0" }
    get root_path
    expect(response.body).to include('class="line setpoint"', "Set heater to", "Water then")
  end

  it "shows recent messages" do
    create(:text_message, pool: pool, body: "Set the heater to 93°F.")
    get root_path
    expect(response.body).to include("Set the heater to 93°F.")
  end
end
