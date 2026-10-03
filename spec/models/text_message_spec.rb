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
