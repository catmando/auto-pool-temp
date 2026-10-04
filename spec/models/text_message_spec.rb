require "rails_helper"

RSpec.describe TextMessage do
  it { is_expected.to belong_to(:pool).optional }
  it { is_expected.to validate_presence_of(:body) }
  it { is_expected.to validate_inclusion_of(:direction).in_array(%w[outbound inbound]) }

  describe ".deliver" do
    let(:pool) { create(:pool) }
    let(:sender) { FakeSmsSender.new }

    it "sends to the pool's phone and records the result" do
      message = described_class.deliver(pool: pool, body: "Hi", sender: sender)
      expect(sender.deliveries).to eq([ { to: "+15125550100", body: "Hi" } ])
      expect(message.reload).to have_attributes(direction: "outbound", to: "+15125550100", provider_sid: "SM1",
                                                status: "queued", pool: pool)
      expect(message).not_to be_failed
    end

    it "records failures instead of raising" do
      sender.fail_with = "invalid number"
      message = described_class.deliver(pool: pool, body: "Hi", sender: sender)
      expect(message.reload).to have_attributes(status: "failed", error: "invalid number")
      expect(message).to be_failed
    end

    it "uses the app-wide sender by default" do
      described_class.deliver(pool: pool, body: "Hi")
      expect(Sms.sender.deliveries.size).to eq(1)
    end
  end
end

RSpec.describe TextMessage, "channels" do
  it { is_expected.to validate_inclusion_of(:channel).in_array(%w[sms telegram]) }

  it "routes to the pool's channel and address" do
    pool = create(:pool, :telegram)
    message = described_class.deliver(pool: pool, body: "Hi")
    expect(message).to have_attributes(channel: "telegram", to: "424242", status: "queued")
    expect(TelegramBot.sender.deliveries.size).to eq(1)
  end

  it "can force a channel" do
    pool = create(:pool, :telegram)
    described_class.deliver(pool: pool, body: "Hi", channel: "sms")
    expect(Sms.sender.deliveries.last).to include(to: "+15125550100")
  end

  it "fails cleanly with no address" do
    pool = create(:pool, notification_channel: "telegram")
    message = described_class.deliver(pool: pool, body: "Hi")
    expect(message).to be_failed
    expect(message.error).to include("no Telegram address")
  end
end
