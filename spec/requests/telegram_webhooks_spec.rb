require "rails_helper"

RSpec.describe "Telegram webhook" do
  let!(:pool) { create(:pool, :telegram, assumed_setpoint: 91) }
  let(:secret) { "s3cret" }

  before { allow(TelegramBot).to receive(:webhook_secret).and_return(secret) }

  def update(text, chat_id: 424242, type: "private")
    { update_id: 1, message: { message_id: 5, text: text, chat: { id: chat_id, type: type } } }
  end

  def post_update(payload, token: secret)
    post telegram_webhook_path, params: payload, as: :json, headers: { "X-Telegram-Bot-Api-Secret-Token" => token }
  end

  it "handles messages from a linked chat" do
    post_update(update("status"))
    expect(response).to have_http_status(:ok)
    expect(TelegramBot.sender.deliveries.last).to include(to: "424242")
    expect(TelegramBot.sender.last_body).to include("Target now: 91°F")
  end

  it "links a chat via /start <token>" do
    other = create(:pool)
    token = TelegramLink.start!(other)
    post_update(update("/start #{token}", chat_id: 555))
    expect(other.reload.telegram_chat_id).to eq("555")
  end

  it "ignores group chats and non-text updates" do
    post_update(update("status", type: "group"))
    post_update({ update_id: 2, edited_message: { text: "x" } })
    expect(response).to have_http_status(:ok)
    expect(TextMessage.count).to eq(0)
  end

  it "rejects a missing or wrong secret" do
    post_update(update("status"), token: "wrong")
    expect(response).to have_http_status(:forbidden)
  end

  it "is unavailable without a bot token" do
    allow(TelegramBot).to receive(:webhook_secret).and_return(nil)
    post_update(update("status"))
    expect(response).to have_http_status(:service_unavailable)
  end
end
