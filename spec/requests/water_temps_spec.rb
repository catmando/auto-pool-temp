require "rails_helper"

RSpec.describe "Reporting the water temperature" do
  let(:pool) { create(:pool, assumed_setpoint: 90) }

  before { sign_in_as(pool.user) }

  it "records a reading" do
    patch water_temp_path, params: { water_temp: "86.5" }
    expect(response).to redirect_to(root_path)
    expect(pool.reload).to have_attributes(water_temp: 86.5, water_temp_source: "reported")
    follow_redirect!
    expect(response.body).to include("your reading of 87°F")
  end

  it "rejects nonsense" do
    patch water_temp_path, params: { water_temp: "warm" }
    expect(flash[:alert]).to include("between 32 and 110")
  end
end
