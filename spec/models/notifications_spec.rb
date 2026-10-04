require "rails_helper"

RSpec.describe Notifications do
  it "lists channels with labels" do
    expect(described_class.channels).to eq(%w[sms telegram])
    expect(described_class.label("telegram")).to eq("Telegram")
  end

  it "picks the sender for a channel" do
    expect(described_class.sender("sms")).to equal(Sms.sender)
    expect(described_class.sender("telegram")).to equal(TelegramBot.sender)
    expect { described_class.sender("pigeon") }.to raise_error(ArgumentError)
  end

  it "finds the pool's address for a channel" do
    pool = build(:pool, :telegram)
    expect(described_class.address(pool)).to eq("424242")
    expect(described_class.address(pool, "sms")).to eq("+15125550100")
  end
end
