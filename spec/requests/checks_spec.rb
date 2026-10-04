require "rails_helper"

RSpec.describe "Manual checks" do
  let(:pool) { create(:pool, assumed_setpoint: 85) }

  before { sign_in_as(pool.user) }

  it "previews without sending" do
    post checks_path, params: { notify: "0" }
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to match(/\ARecommended 9[12]°F \(preview, nothing sent\)\.\z/)
    expect(Sms.sender.deliveries).to be_empty
    expect(pool.recommendations.count).to eq(1)
  end

  it "sends an alert when a change is needed" do
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to match(/\ARecommended 9[12]°F and sent an alert by Text message \(Twilio\)\.\z/)
    expect(Sms.sender.deliveries.size).to eq(1)
  end

  it "sends by Telegram when that is the channel" do
    pool.update!(notification_channel: "telegram", telegram_chat_id: "42")
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to include("by Telegram")
    expect(TelegramBot.sender.deliveries.last[:to]).to eq("42")
    expect(Sms.sender.deliveries).to be_empty
  end

  it "says when no change is needed" do
    pool.update!(assumed_setpoint: 91)
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to include("No change needed")
  end

  it "says when nothing was sent because the address isn't confirmed" do
    pool.update!(phone_verified_at: nil)
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to include("confirm where alerts go")
    expect(Sms.sender.deliveries).to be_empty
  end

  it "says when alerts are paused" do
    pool.update!(notifications_enabled: false)
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to include("Alerts are paused")
  end

  it "reports a failed alert" do
    Sms.sender.fail_with = "bad number"
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to include("the alert failed: bad number")
  end

  it "reports forecast failures" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    post checks_path, params: { notify: "1" }
    expect(flash[:alert]).to eq("Check failed: down")
  end
end
