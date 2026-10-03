require "rails_helper"

RSpec.describe "Setting up the app" do
  it "goes from sign-up through settings to a first recommendation" do
    visit root_path
    fill_in "Email", with: "me@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_button "Create account"

    expect(page).to have_content("Set up your pool")
    fill_in "Location", with: "Austin, Texas, US"
    fill_in "Latitude", with: "30.27"
    fill_in "Longitude", with: "-97.74"
    fill_in "Time zone", with: "America/Chicago"
    fill_in "Mobile number", with: "512-555-0100"
    fill_in "Heats up (°F per day)", with: "4"
    click_button "Save settings"

    expect(page).to have_content("Settings saved")
    expect(page).to have_content("not yet known")
    click_button "Check & text if needed"

    expect(page).to have_content("Recommended 91°F and sent a text.")
    expect(page).to have_content("assumed: you followed the last text")
    expect(page).to have_css("svg.chart")
    expect(Sms.sender.deliveries.first[:to]).to eq("+15125550100")

    fill_in "Actually set to", with: "86"
    click_button "Update"
    expect(page).to have_content("the heater is set to 86°F")

    click_link "Texts"
    expect(page).to have_content("set the heater to 91°F")
  end
end
