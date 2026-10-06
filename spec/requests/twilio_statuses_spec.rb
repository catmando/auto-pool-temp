require "rails_helper"

RSpec.describe "Twilio delivery status callback" do
  let(:pool) { create(:pool) }
  let!(:message) { create(:text_message, pool: pool, status: "queued", provider_sid: "SM42") }
  let(:url) { "http://www.example.com/twilio/status" }

  def signature(params) = Twilio::Security::RequestValidator.new("secret").build_signature_for(url, params)

  def report(params, signed: true)
    post twilio_status_path, params: params, headers: { "X-Twilio-Signature" => signed ? signature(params) : "forged" }
  end

  around do |example|
    original = ENV["TWILIO_AUTH_TOKEN"]
    ENV["TWILIO_AUTH_TOKEN"] = "secret"
    example.run
  ensure
    ENV["TWILIO_AUTH_TOKEN"] = original
  end

  it "records delivery" do
    report({ "MessageSid" => "SM42", "MessageStatus" => "delivered" })
    expect(response).to have_http_status(:no_content)
    expect(message.reload).to have_attributes(status: "delivered", error: nil)
  end

  it "records a carrier rejection with a readable error" do
    report({ "MessageSid" => "SM42", "MessageStatus" => "undelivered", "ErrorCode" => "30034" })
    expect(message.reload.status).to eq("undelivered")
    expect(message.error).to start_with("Twilio error 30034")
  end

  it "ignores messages it doesn't know" do
    report({ "MessageSid" => "SM999", "MessageStatus" => "delivered" })
    expect(response).to have_http_status(:no_content)
    expect(message.reload.status).to eq("queued")
  end

  it "rejects unsigned reports" do
    report({ "MessageSid" => "SM42", "MessageStatus" => "delivered" }, signed: false)
    expect(response).to have_http_status(:forbidden)
    expect(message.reload.status).to eq("queued")
  end
end
