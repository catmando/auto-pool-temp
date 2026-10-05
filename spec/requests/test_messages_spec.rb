require "rails_helper"

RSpec.describe "Send test message (Advanced settings)" do
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 85, has_cover: true, cover_on: true) }

  before { sign_in_as(pool.user) }

  it "has the button in Advanced" do
    get edit_pool_path
    expect(response.body).to include("Send test message", 'form="test-message-form"', 'id="test-message-form"')
  end

  it "sends the alert the current plan would send right now" do
    post test_message_path
    expect(flash[:notice]).to eq("Test message sent by Telegram: the alert your pool would get right now.")
    body = TelegramBot.sender.last_body
    plan = pool.recommendations.recent.first
    expect(body).to include("Your heater should be set to: #{plan.target_temp}°F", "Cover should be on when not in use.",
                            "Respond with current pool temperature to improve system accuracy.")
    expect(body).to eq(TestMessagesController.body_for(pool.reload, plan))
    expect(pool.text_messages.last).to have_attributes(direction: "outbound", channel: "telegram", body: body)
  end

  it "doesn't change what the app assumes about the heater, cover, or pump" do
    expect { post test_message_path }
      .not_to(change { pool.reload.attributes.slice("assumed_setpoint", "cover_on", "pump_extended", "setpoint_updated_at") })
  end

  it "explains a failure" do
    TelegramBot.sender.fail_with = "bot was blocked by the user"
    post test_message_path
    expect(flash[:alert]).to eq("The test message failed: bot was blocked by the user")
  end

  it "asks to connect Telegram first" do
    pool.update!(telegram_chat_id: nil)
    post test_message_path
    expect(flash[:alert]).to include("Connect Telegram first")
    expect(TelegramBot.sender.deliveries).to be_empty
  end

  it "reports a forecast failure" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    post test_message_path
    expect(flash[:alert]).to include("down")
  end
end
