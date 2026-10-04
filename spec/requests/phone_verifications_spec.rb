require "rails_helper"

RSpec.describe "Confirming a phone number" do
  let(:pool) { create(:pool, :unverified) }

  before { sign_in_as(pool.user) }

  def code = Sms.sender.last_body[/\d{6}/]

  it "texts a code and shows the code form" do
    post phone_verification_path
    expect(response).to redirect_to(edit_pool_path)
    expect(flash[:notice]).to include("Code sent")
  end

  it "confirms with the right code" do
    post phone_verification_path
    patch phone_verification_path, params: { code: code }
    expect(flash[:notice]).to eq("Phone number confirmed.")
    expect(pool.reload).to be_phone_verified
  end

  it "rejects a wrong code" do
    post phone_verification_path
    patch phone_verification_path, params: { code: "x" }
    expect(flash[:alert]).to eq("That code isn't right.")
  end

  it "reports send problems" do
    Sms.sender.fail_with = "error 30034"
    post phone_verification_path
    expect(flash[:alert]).to include("30034")
  end
end

RSpec.describe "Confirming a phone number when the carrier blocks the text" do
  let(:pool) { create(:pool, :unverified) }

  before do
    sign_in_as(pool.user)
    Sms.sender.lookup_result = [ "undelivered", 30034 ]
  end

  it "says the code wasn't delivered, and why" do
    post phone_verification_path
    expect(flash[:alert]).to include("wasn't delivered", "isn't A2P 10DLC registered")
  end

  it "records the carrier's answer on the message" do
    post phone_verification_path
    expect(TextMessage.last).to have_attributes(status: "undelivered")
    expect(TextMessage.last.error).to include("30034")
  end
end
