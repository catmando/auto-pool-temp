require "rails_helper"

RSpec.describe "Pump running around the clock" do
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 90, pump_extended: true) }

  before { sign_in_as(pool.user) }

  it "shows on the dashboard and can be switched back" do
    get root_path
    expect(response.body).to include("running around the clock")
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
