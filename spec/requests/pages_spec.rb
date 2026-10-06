require "rails_helper"

# Carrier reviewers (A2P 10DLC) check these pages without signing in.
RSpec.describe "Public pages" do
  it "describes the text alert program, with how to opt in and out" do
    get sms_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(SmsProgram::NAME, SmsProgram::SENDER, SmsProgram::CONTACT_EMAIL,
                                      "Message and data rates may apply", "STOP", "HELP", "up to 3 messages a day")
  end

  it "has a privacy policy that keeps phone numbers and consent private" do
    get privacy_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No mobile information will be shared with third parties or affiliates",
                                      "opt-in data and consent will not be shared with any third parties")
  end

  it "links both from every page's footer" do
    get privacy_path
    expect(response.body).to include(%(href="#{sms_path}"), %(href="#{privacy_path}"))
  end
end
