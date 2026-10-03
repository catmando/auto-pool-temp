require "rails_helper"

RSpec.describe "Manual checks" do
  let(:pool) { create(:pool, assumed_setpoint: 85) }

  before { sign_in_as(pool.user) }

  it "previews without texting" do
    post checks_path, params: { notify: "0" }
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Recommended 91°F (preview, nothing sent).")
    expect(Sms.sender.deliveries).to be_empty
    expect(pool.recommendations.count).to eq(1)
  end

  it "texts when a change is needed" do
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to eq("Recommended 91°F and sent a text.")
    expect(Sms.sender.deliveries.size).to eq(1)
  end

  it "says when no change is needed" do
    pool.update!(assumed_setpoint: 91)
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to include("No change needed")
  end

  it "reports a failed text" do
    Sms.sender.fail_with = "bad number"
    post checks_path, params: { notify: "1" }
    expect(flash[:notice]).to include("the text failed: bad number")
  end

  it "reports forecast failures" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    post checks_path, params: { notify: "1" }
    expect(flash[:alert]).to eq("Check failed: down")
  end
end
