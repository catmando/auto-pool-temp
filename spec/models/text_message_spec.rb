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

RSpec.describe TextMessage, "delivery status" do
  let(:pool) { create(:pool) }
  let(:sender) { FakeSmsSender.new }
  let(:message) { described_class.deliver(pool: pool, body: "Hi", sender: sender) }

  it "starts out pending" do
    expect(message).to be_delivery_pending
  end

  it "records a carrier rejection in plain English" do
    sender.lookup_result = [ "undelivered", 30034 ]
    message.refresh_delivery_status!(sender: sender)
    expect(message.reload).to have_attributes(status: "undelivered")
    expect(message.error).to include("30034", "isn't A2P 10DLC registered")
    expect(message).to be_failed
    expect(message).not_to be_delivery_pending
  end

  it "links to Twilio docs for unknown codes" do
    expect(described_class.describe_twilio_error(12345)).to include("twilio.com/docs/api/errors/12345")
    expect(described_class.describe_twilio_error(nil)).to be_nil
  end

  it "marks delivered texts" do
    message.refresh_delivery_status!(sender: sender)
    expect(message.reload).to have_attributes(status: "delivered", error: nil)
  end

  it "leaves final, inbound, and Telegram messages alone" do
    expect(sender).not_to receive(:lookup)
    create(:text_message, pool: pool, status: "delivered", provider_sid: "SM1").refresh_delivery_status!(sender: sender)
    create(:text_message, pool: pool, direction: "inbound", status: "received").refresh_delivery_status!(sender: sender)
    create(:text_message, pool: pool, channel: "telegram", status: "sent", provider_sid: "7").refresh_delivery_status!(sender: sender)
  end

  it "doesn't raise when the lookup fails" do
    allow(sender).to receive(:lookup).and_raise(Sms::Error, "down")
    expect { message.refresh_delivery_status!(sender: sender) }.not_to raise_error
    expect(message.reload.status).to eq("queued")
  end

  it "polls until a final status" do
    sender.lookup_result = [ "undelivered", 30034 ]
    message.await_delivery_status!(wait: 0, sender: sender)
    expect(message.status).to eq("undelivered")
  end
end
