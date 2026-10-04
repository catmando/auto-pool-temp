require "rails_helper"

RSpec.describe TelegramLink do
  let(:pool) { create(:pool) }

  it "makes a one-time token usable in a t.me deep link" do
    token = described_class.start!(pool)
    expect(token).to match(/\A[A-Za-z0-9_-]{20,64}\z/)
    expect(described_class.url(token, username: "pool_temp_bot")).to eq("https://t.me/pool_temp_bot?start=#{token}")
  end

  it "links the chat and spends the token" do
    token = described_class.start!(pool)
    expect(described_class.complete(token, chat_id: 123)).to eq(pool)
    expect(pool.reload).to have_attributes(telegram_chat_id: "123", telegram_link_token: nil)
    expect(pool).to be_telegram_linked
    expect(described_class.complete(token, chat_id: 999)).to be_nil
  end

  it "rejects expired tokens" do
    token = described_class.start!(pool, now: 31.minutes.ago)
    expect(described_class.complete(token, chat_id: 123)).to be_nil
    expect(pool.reload.telegram_chat_id).to be_nil
  end

  it "rejects blank and unknown tokens" do
    expect(described_class.complete(nil, chat_id: 1)).to be_nil
    expect(described_class.complete("nope", chat_id: 1)).to be_nil
  end
end
