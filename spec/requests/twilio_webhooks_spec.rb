require "rails_helper"

RSpec.describe "Twilio inbound SMS webhook" do
  let!(:pool) { create(:pool, assumed_setpoint: 91) }
  let(:params) { { "From" => "+15125550100", "Body" => "status" } }
  let(:url) { "http://www.example.com/twilio/sms" }

  def signature(token, url, params) = Twilio::Security::RequestValidator.new(token).build_signature_for(url, params)

  around do |example|
    original = ENV["TWILIO_AUTH_TOKEN"]
    ENV["TWILIO_AUTH_TOKEN"] = "secret"
    example.run
  ensure
    ENV["TWILIO_AUTH_TOKEN"] = original
  end

  it "handles a correctly signed message and returns empty TwiML" do
    post twilio_sms_path, params: params, headers: { "X-Twilio-Signature" => signature("secret", url, params) }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<Response></Response>")
    expect(Sms.sender.deliveries.last[:body]).to include("Target now: 91°F")
  end

  it "rejects a bad signature" do
    post twilio_sms_path, params: params, headers: { "X-Twilio-Signature" => "forged" }
    expect(response).to have_http_status(:forbidden)
    expect(TextMessage.count).to eq(0)
  end

  it "is unavailable until Twilio is configured" do
    ENV["TWILIO_AUTH_TOKEN"] = nil
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    post twilio_sms_path, params: params
    expect(response).to have_http_status(:service_unavailable)
  end
end
