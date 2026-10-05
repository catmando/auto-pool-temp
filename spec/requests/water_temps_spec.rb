require "rails_helper"

RSpec.describe "Reporting the water temperature" do
  let(:pool) { create(:pool, assumed_setpoint: 90) }

  before { sign_in_as(pool.user) }

  it "logs a reading with what the model expected, without changing the plan's inputs" do
    expect { patch water_temp_path, params: { water_temp: "86.5" } }.to change(pool.pool_logs, :count).by(1)
    expect(pool.pool_logs.last).to have_attributes(kind: "water_reading", water_temp: 86.5, expected_water_temp: 90, source: "web")
    expect(flash[:notice]).to eq("Logged the water at 86.5°F (expected about 90°F).")
    expect(pool.reload.water_temp).to be_nil
    follow_redirect!
    expect(response.body).to include("Last reading 87°F", "Logging actual temps helps improve the algorithm's accuracy.")
  end

  it "rejects nonsense" do
    patch water_temp_path, params: { water_temp: "warm" }
    expect(flash[:alert]).to include("between 32 and 110")
  end
end
