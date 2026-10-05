require "rails_helper"

RSpec.describe "Pump running around the clock" do
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 90, pump_extended: true) }

  before { sign_in_as(pool.user) }

  it "shows the recommended pump setting on the dashboard, and records a change" do
    get root_path
    expect(response.body).to match(%r{<dt>Pump</dt><dd>(Normal schedule|Leave on 24 hours)})
    patch pump_path, params: { extended: "0" }
    expect(pool.reload.pump_extended).to be false
    expect(flash[:notice]).to include("normal schedule")
  end

  it "has its threshold in Advanced settings" do
    get edit_pool_path
    expect(response.body).to include("Suggest running the pump around the clock")
    patch pool_path(format: :json), params: { pool: { pump_boost_threshold: "5" } }
    expect(pool.reload.pump_boost_threshold).to eq(5)
  end
end
