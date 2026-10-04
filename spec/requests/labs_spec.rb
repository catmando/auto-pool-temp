require "rails_helper"

RSpec.describe "Planner lab" do
  let(:pool) { create(:pool) }

  before { sign_in_as(pool.user) }

  it "compares every planner on the live forecast and made-up weather" do
    get lab_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your forecast", "Cold snap", "Heat wave", "Choppy fall", "Search", "Follow",
                                     "Avg discomfort", "setpoint-marker")
  end

  it "still shows the made-up weather when the forecast is down" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    get lab_path
    expect(response.body).not_to include("Your forecast")
    expect(response.body).to include("Cold snap")
  end
end
