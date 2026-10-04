require "rails_helper"

RSpec.describe "Pool settings" do
  let(:pool) { create(:pool, :telegram) }

  before { sign_in_as(pool.user) }

  it "shows the location map, Telegram status, and settings" do
    allow(TelegramBot).to receive(:configured?).and_return(true)
    get edit_pool_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="location-map"', "Austin, Texas, US", "Confirm location",
                                     "Alerts in Telegram", "Connected ✓", "Warm-day threshold",
                                     "At 65°F air the pool should be 91°F", "Search")
  end

  it "has no channel picker, phone number, or forecast-days setting" do
    get edit_pool_path
    expect(response.body).not_to include("notification_channel", "phone_number", "forecast_days")
  end

  it "updates settings" do
    patch pool_path, params: { pool: { hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_day: 4.5,
                                       warm_day_threshold: 75, checks_per_day: 3, strategy: "follow" } }
    expect(response).to redirect_to(root_path)
    expect(pool.reload).to have_attributes(hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_day: 4.5,
                                           warm_day_threshold: 75, checks_per_day: 3, strategy: "follow")
  end

  it "ignores settings that aren't on the page any more" do
    patch pool_path, params: { pool: { notification_channel: "sms", forecast_days: 3, name: "Pool" } }
    expect(pool.reload).to have_attributes(notification_channel: "telegram", forecast_days: 16)
  end

  it "re-renders invalid settings" do
    patch pool_path, params: { pool: { heat_rate_per_day: 0 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Heat rate per day must be greater than 0")
  end

  it "asks to connect Telegram when it isn't yet" do
    pool.update!(telegram_chat_id: nil)
    patch pool_path, params: { pool: { name: "Backyard" } }
    expect(response).to redirect_to(edit_pool_path(anchor: "delivery"))
    expect(flash[:notice]).to include("Connect Telegram")
  end

  it "doesn't nag when alerts are off" do
    pool.update!(telegram_chat_id: nil)
    patch pool_path, params: { pool: { notifications_enabled: "0" } }
    expect(response).to redirect_to(root_path)
  end
end

RSpec.describe "Pool settings autosave and plan" do
  let(:pool) { create(:pool, :telegram) }

  before { sign_in_as(pool.user) }

  it "saves a single changed field as JSON" do
    patch pool_path(format: :json), params: { pool: { warm_day_threshold: 40 } }
    expect(response.parsed_body).to eq("ok" => true)
    expect(pool.reload.warm_day_threshold).to eq(40)
  end

  it "returns validation errors as JSON" do
    patch pool_path(format: :json), params: { pool: { heat_rate_per_day: 0 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to include("Heat rate per day must be greater than 0")
  end

  it "shows the plan as a frame on Settings, re-planned after a change" do
    get edit_pool_path
    expect(response.body).to include('turbo-frame id="settings_plan"', "Changes save automatically")
    get plan_path
    expect(response.body).to include('<turbo-frame id="settings_plan">', 'class="line setpoint"', "Average error")
    first = pool.recommendations.recent.first
    travel 1.minute do
      patch pool_path(format: :json), params: { pool: { warm_day_threshold: 40 } }
      get plan_path
      expect(pool.recommendations.recent.first).not_to eq(first)
    end
  end

  it "asks for a location before showing a plan" do
    pool.update!(latitude: nil, longitude: nil)
    get plan_path
    expect(response.body).to include("Set a location")
  end
end
