require "rails_helper"

RSpec.describe Sms::TwilioSetup do
  let(:number) do
    double("number", sid: "PN1", phone_number: "+15550001111", sms_url: "https://old.example/twilio/sms", sms_method: "POST")
  end
  let(:number_context) { double("number_context") }
  let(:incoming) { double("incoming_phone_numbers") }
  let(:client) { double("client") }

  subject(:setup) { described_class.new(client: client) }

  before do
    allow(Sms).to receive(:config) { |key| { account_sid: "AC1", auth_token: "t", from_number: "+15550001111" }[key] }
    allow(client).to receive(:incoming_phone_numbers) { |sid = nil| sid ? number_context : incoming }
    allow(incoming).to receive(:list).with(phone_number: "+15550001111").and_return([ number ])
  end

  it "reports missing settings" do
    allow(Sms).to receive(:config).and_return(nil)
    expect(setup.missing_settings).to eq(%i[account_sid auth_token from_number])
    expect(setup).not_to be_configured
    expect { setup.status }.to raise_error(Sms::Error, /missing: account_sid/)
  end

  it "shows the number's current webhook" do
    expect(setup.status).to eq(from_number: "+15550001111", sms_url: "https://old.example/twilio/sms", sms_method: "POST")
  end

  it "complains when the number isn't on the account" do
    allow(incoming).to receive(:list).and_return([])
    expect { setup.status }.to raise_error(Sms::Error, /isn't a phone number on this Twilio account/)
  end

  it "points the webhook at the app" do
    expect(number_context).to receive(:update).with(sms_url: "https://abc.trycloudflare.com/twilio/sms", sms_method: "POST")
    expect(setup.point_webhook_at!("https://abc.trycloudflare.com/")).to eq("https://abc.trycloudflare.com/twilio/sms")
  end
end
