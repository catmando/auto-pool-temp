require "rails_helper"

RSpec.describe TelegramBot do
  let(:token) { "123:abc" }
  let(:api) { "https://api.telegram.org/bot#{token}" }

  around do |example|
    original = ENV["TELEGRAM_BOT_TOKEN"]
    ENV["TELEGRAM_BOT_TOKEN"] = token
    example.run
  ensure
    ENV["TELEGRAM_BOT_TOKEN"] = original
  end

  describe "configuration" do
    it "reads the token from ENV" do
      expect(described_class).to be_configured
    end

    it "derives a stable webhook secret from the token" do
      expect(described_class.webhook_secret).to match(/\A[0-9a-f]{48}\z/)
      expect(described_class.webhook_secret).to eq(described_class.webhook_secret)
    end

    it "logs instead of sending when unconfigured" do
      ENV["TELEGRAM_BOT_TOKEN"] = nil
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      described_class.sender = nil
      expect(described_class.sender).to be_a(Sms::LogSender)
      expect(described_class.webhook_secret).to be_nil
    end
  end

  describe TelegramBot::Client do
    subject(:client) { described_class.new(token: token) }

    it "sends messages" do
      stub = stub_request(:post, "#{api}/sendMessage")
        .with(body: hash_including("chat_id" => "42", "text" => "Hi"))
        .to_return(body: { ok: true, result: { message_id: 7 } }.to_json)
      expect(client.deliver(to: "42", body: "Hi")).to eq(Sms::Delivery.new(sid: "7", status: "sent"))
      expect(stub).to have_been_requested
    end

    it "raises Sms::Error when Telegram refuses" do
      stub_request(:post, "#{api}/sendMessage").to_return(status: 403, body: { ok: false, description: "bot was blocked by the user" }.to_json)
      expect { client.deliver(to: "42", body: "Hi") }.to raise_error(Sms::Error, /blocked/)
    end

    it "wraps network errors" do
      stub_request(:post, "#{api}/getMe").to_raise(SocketError.new("offline"))
      expect { client.username }.to raise_error(TelegramBot::Error, /offline/)
    end

    it "looks up the bot's username" do
      stub_request(:post, "#{api}/getMe").to_return(body: { ok: true, result: { username: "pool_temp_bot" } }.to_json)
      expect(client.username).to eq("pool_temp_bot")
    end

    it "registers the webhook with the secret" do
      stub = stub_request(:post, "#{api}/setWebhook")
        .with(body: hash_including("url" => "https://x.test/telegram/webhook", "secret_token" => TelegramBot.webhook_secret))
        .to_return(body: { ok: true, result: true }.to_json)
      client.set_webhook("https://x.test/telegram/webhook")
      expect(stub).to have_been_requested
    end

    it "needs a token" do
      expect { described_class.new(token: nil).username }.to raise_error(TelegramBot::Error, /not configured/)
    end
  end
end
