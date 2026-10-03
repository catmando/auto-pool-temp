require "rails_helper"

RSpec.describe "Reporting the heater setting" do
  let(:pool) { create(:pool, assumed_setpoint: 85) }

  before { sign_in_as(pool.user) }

  it "records the actual setting" do
    patch setpoint_path, params: { assumed_setpoint: "87" }
    expect(response).to redirect_to(root_path)
    expect(pool.reload).to have_attributes(assumed_setpoint: 87, setpoint_source: "user_reported")
  end

  it "rejects nonsense" do
    patch setpoint_path, params: { assumed_setpoint: "hot" }
    expect(flash[:alert]).to include("between 40 and 110")
    expect(pool.reload.assumed_setpoint).to eq(85)
  end
end
