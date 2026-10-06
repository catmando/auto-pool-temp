require "rails_helper"

RSpec.describe "Pool settings" do
  let(:pool) { create(:pool, :telegram) }

  before { sign_in_as(pool.user) }

  it "shows the location map, Telegram status, and settings" do
    allow(TelegramBot).to receive(:configured?).and_return(true)
    get edit_pool_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="location-map"', "Austin, Texas, US", "Confirm location",
                                     "Alerts in Telegram", "Connected ✓", "Warm-day threshold", "ZIP code", "e.g. 14618",
                                     "At 65°F air the pool should be 91°F", "Search")
  end

  it "has no forecast-days setting" do
    get edit_pool_path
    expect(response.body).not_to include("forecast_days")
  end

  it "updates settings" do
    patch pool_path, params: { pool: { hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_hour: 1.5,
                                       warm_day_threshold: 75, checks_per_day: 3, strategy: "follow" } }
    expect(response).to redirect_to(root_path)
    expect(pool.reload).to have_attributes(hot_air_temp: 90, cold_pool_temp: 100, heat_rate_per_hour: 1.5,
                                           warm_day_threshold: 75, checks_per_day: 3, strategy: "follow")
  end

  it "ignores settings that aren't on the page any more" do
    patch pool_path, params: { pool: { forecast_days: 3, name: "Pool" } }
    expect(pool.reload).to have_attributes(forecast_days: 16)
  end

  it "re-renders invalid settings" do
    patch pool_path, params: { pool: { heat_rate_per_hour: 0 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Heat rate per hour must be greater than 0")
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
    patch pool_path(format: :json), params: { pool: { heat_rate_per_hour: 0 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to include("Heat rate per hour must be greater than 0")
  end

  it "says changes save automatically, with no plan chart on Settings" do
    get edit_pool_path
    expect(response.body).to include("Changes save automatically")
    expect(response.body).not_to include("settings_plan")
  end
end

RSpec.describe "Pool settings for text alerts" do
  let(:pool) { create(:pool, :telegram, phone_number: nil, phone_verified_at: nil, sms_consent_at: nil) }

  before { sign_in_as(pool.user) }

  it "offers text alerts with the consent wording and links to the program and privacy pages" do
    get edit_pool_path
    expect(response.body).to include("Send alerts by", "Text message", "Mobile number (for text alerts)",
                                      ERB::Util.html_escape(SmsProgram::CONSENT), %(href="#{sms_path}"), %(href="#{privacy_path}"))
  end

  it "won't switch to text alerts without the consent box" do
    patch pool_path, params: { pool: { notification_channel: "sms", phone_number: "+15125550100", sms_consent: "0" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Check the box agreeing to receive text alerts")
    expect(pool.reload.notification_channel).to eq("telegram")
  end

  it "records consent and texts a confirmation code" do
    patch pool_path, params: { pool: { notification_channel: "sms", phone_number: "+15125550100", sms_consent: "1" } }
    expect(response).to redirect_to(edit_pool_path(anchor: "delivery"))
    expect(flash[:notice]).to include("We texted a code")
    expect(pool.reload).to have_attributes(notification_channel: "sms", sms_consent_given?: true)
    expect(Sms.sender.deliveries.last).to include(to: "+15125550100")
  end

  it "shows the text alert card with a code form once a code is sent" do
    patch pool_path, params: { pool: { notification_channel: "sms", phone_number: "+15125550100", sms_consent: "1" } }
    follow_redirect!
    expect(response.body).to include("Alerts by text message", "not confirmed yet", "Confirm", "Send a new code")
  end

  it "shows a confirmed number" do
    pool.update!(notification_channel: "sms", phone_number: "+15125550100", phone_verified_at: Time.current, sms_consent: true)
    get edit_pool_path
    expect(response.body).to include("Alerts by text message", "Confirmed ✓")
  end
end
