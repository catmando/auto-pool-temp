require "rails_helper"

RSpec.describe Sms::TwilioSender do
  let(:env) { { "TWILIO_ACCOUNT_SID" => "AC123", "TWILIO_AUTH_TOKEN" => "secret", "TWILIO_FROM_NUMBER" => "+15550001111" } }

  around do |example|
    saved = env.keys.to_h { |k| [ k, ENV[k] ] }
    example.run
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  describe ".configured?" do
    it "is true with all three settings" do
      env.each { |k, v| ENV[k] = v }
      expect(described_class).to be_configured
    end

    it "is false when any is missing" do
      env.each { |k, v| ENV[k] = v }
      ENV["TWILIO_AUTH_TOKEN"] = nil
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      expect(described_class).not_to be_configured
    end
  end

  describe "#deliver" do
    let(:messages) { double("messages") }
    let(:client) { double("client", messages: messages) }

    before { env.each { |k, v| ENV[k] = v } }

    it "creates a Twilio message from the configured number" do
      expect(messages).to receive(:create).with(from: "+15550001111", to: "+15125550100", body: "Hi")
        .and_return(double(sid: "SM9", status: "queued"))
      expect(described_class.new(client: client).deliver(to: "+15125550100", body: "Hi"))
        .to eq(Sms::Delivery.new(sid: "SM9", status: "queued"))
    end

    it "wraps Twilio errors" do
      allow(messages).to receive(:create).and_raise(Twilio::REST::TwilioError.new("bad"))
      expect { described_class.new(client: client).deliver(to: "+1", body: "Hi") }.to raise_error(Sms::Error, "bad")
    end
  end
end

RSpec.describe Sms do
  it "falls back to logging when Twilio isn't configured" do
    Sms.sender = nil
    allow(Sms::TwilioSender).to receive(:configured?).and_return(false)
    expect(Sms.sender).to be_a(Sms::LogSender)
  end

  it "uses Twilio when configured" do
    Sms.sender = nil
    allow(Sms::TwilioSender).to receive(:configured?).and_return(true)
    expect(Sms.sender).to be_a(Sms::TwilioSender)
  end

  it "logs without sending" do
    expect(Sms::LogSender.new.deliver(to: "+1", body: "x")).to eq(Sms::Delivery.new(sid: nil, status: "logged"))
  end
end

RSpec.describe Sms::TwilioSender, "#lookup" do
  it "fetches the message's current status and error code" do
    context = double(fetch: double(status: "undelivered", error_code: 30034))
    client = double("client")
    allow(client).to receive(:messages).with("SM1").and_return(context)
    delivery, code = described_class.new(client: client).lookup("SM1")
    expect(delivery).to eq(Sms::Delivery.new(sid: "SM1", status: "undelivered"))
    expect(code).to eq(30034)
  end
end
