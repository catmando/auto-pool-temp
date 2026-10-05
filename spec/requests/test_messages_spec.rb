require "rails_helper"

RSpec.describe "Send test message (Advanced settings)" do
  let(:pool) { create(:pool, :telegram) }

  before { sign_in_as(pool.user) }

  it "has the button in Advanced" do
    get edit_pool_path
    expect(response.body).to include("Send test message", 'form="test-message-form"', 'id="test-message-form"')
  end

  it "sends a test message to the connected chat and logs it" do
    post test_message_path
    expect(flash[:notice]).to eq("Test message sent by Telegram. Check your phone.")
    expect(TelegramBot.sender.deliveries.last).to include(to: "424242", body: TestMessagesController::BODY)
    expect(pool.text_messages.last).to have_attributes(direction: "outbound", channel: "telegram", body: TestMessagesController::BODY)
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
end
