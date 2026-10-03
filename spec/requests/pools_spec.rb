require "rails_helper"

RSpec.describe "Pool settings" do
  let(:pool) { create(:pool) }

  before { sign_in_as(pool.user) }

  it "shows the settings form with the curve preview" do
    get edit_pool_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Target curve", "At 65°F air the pool should be 91°F", "Lookahead")
  end

  it "updates settings" do
    patch pool_path, params: { pool: { hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_day: 4.5,
                                       phone_number: "512-555-0199", checks_per_day: 3, strategy: "linear" } }
    expect(response).to redirect_to(root_path)
    expect(pool.reload).to have_attributes(hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_day: 4.5,
                                           phone_number: "+15125550199", checks_per_day: 3, strategy: "linear")
  end

  it "re-renders invalid settings" do
    patch pool_path, params: { pool: { heat_rate_per_day: 0 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Heat rate per day must be greater than 0")
  end

  it "saves a location picked from search or geolocation" do
    patch pool_path, params: { pool: { location_name: "Here", latitude: "40.0", longitude: "-75.1", time_zone: "America/New_York" } }
    expect(pool.reload).to have_attributes(location_name: "Here", latitude: 40.0, longitude: -75.1, time_zone: "America/New_York")
  end
end
