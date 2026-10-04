require "rails_helper"

RSpec.describe "Pool settings" do
  let(:pool) { create(:pool) }

  before { sign_in_as(pool.user) }

  it "shows the settings form with the curve preview and delivery status" do
    get edit_pool_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Target curve", "At 65°F air the pool should be 91°F", "Lookahead",
                                     "Where alerts go", "confirmed ✓")
  end

  it "updates settings" do
    patch pool_path, params: { pool: { hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_day: 4.5,
                                       checks_per_day: 3, strategy: "linear" } }
    expect(response).to redirect_to(root_path)
    expect(pool.reload).to have_attributes(hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_day: 4.5,
                                           checks_per_day: 3, strategy: "linear")
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

  describe "changing the phone number" do
    it "un-confirms it, texts a code, and asks for it" do
      patch pool_path, params: { pool: { phone_number: "585-278-6308" } }
      expect(response).to redirect_to(edit_pool_path)
      expect(flash[:notice]).to include("We texted a code to +15852786308")
      expect(pool.reload).not_to be_phone_verified
      expect(Sms.sender.deliveries.last).to include(to: "+15852786308")
      expect(Sms.sender.last_body).to match(/code: \d{6}/)
    end

    it "explains when the code can't be sent" do
      Sms.sender.fail_with = "unregistered number"
      patch pool_path, params: { pool: { phone_number: "585-278-6308" } }
      expect(flash[:alert]).to include("code wasn't sent", "unregistered number")
    end
  end

  it "asks to connect Telegram after switching to it" do
    patch pool_path, params: { pool: { notification_channel: "telegram" } }
    expect(response).to redirect_to(edit_pool_path)
    expect(flash[:notice]).to include("Confirm where alerts should go")
  end

  it "doesn't nag when alerts are off" do
    patch pool_path, params: { pool: { notification_channel: "telegram", notifications_enabled: "0" } }
    expect(response).to redirect_to(root_path)
  end
end
