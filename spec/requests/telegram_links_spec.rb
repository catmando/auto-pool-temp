require "rails_helper"

RSpec.describe "Connecting Telegram" do
  let(:pool) { create(:pool) }

  before { sign_in_as(pool.user) }

  context "with a bot configured" do
    before { allow(TelegramBot).to receive(:configured?).and_return(true) }

    it "makes a one-time deep link and shows it" do
      post telegram_link_path
      expect(response).to redirect_to(edit_pool_path)
      token = pool.reload.telegram_link_token
      follow_redirect!
      expect(response.body).to include("https://t.me/pool_temp_bot?start=#{token}", "Open Telegram to connect")
    end

    it "shows a connected chat and can disconnect it" do
      pool.update!(telegram_chat_id: "42", telegram_linked_at: Time.current)
      get edit_pool_path
      expect(response.body).to include("Connected ✓", "Disconnect")
      delete telegram_link_path
      expect(pool.reload.telegram_chat_id).to be_nil
    end
  end

  it "explains when there's no bot yet" do
    allow(TelegramBot).to receive(:configured?).and_return(false)
    post telegram_link_path
    expect(flash[:alert]).to include("isn't set up yet")
    expect(pool.reload.telegram_link_token).to be_nil
  end
end
