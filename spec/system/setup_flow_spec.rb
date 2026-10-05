require "rails_helper"

RSpec.describe "Setting up the app" do
  before { allow(TelegramBot).to receive(:configured?).and_return(true) }

  it "goes from sign-up through location and Telegram to a first alert" do
    visit root_path
    fill_in "Email", with: "me@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_button "Create account"
    expect(page).to have_content("Set up your pool")
    expect(page).to have_content("Not set yet")

    # The map fills these hidden fields (JavaScript); submit them as it would.
    page.driver.submit :patch, location_path, latitude: "43.1159", longitude: "-77.562", name: "14618, Town of Brighton, New York"
    expect(page).to have_content("Location set to 14618, Town of Brighton, New York.")
    expect(page).to have_content("America/New_York")

    find_field("pool[comfort_adjustment]").set("3")
    click_button "Save settings"
    expect(page).to have_content("Connect Telegram to start getting alerts")

    click_button "Connect Telegram"
    token = find_link("Open Telegram to connect")[:href][/start=(.+)\z/, 1]
    InboundMessage.handle(channel: "telegram", from: "9001", body: "/start #{token}") # what Telegram does on Start
    expect(TelegramBot.sender.last_body).to start_with("Connected!")

    click_link "Dashboard"
    expect(page).to have_content("Set heater to") # the dashboard plans on its own
    page.driver.submit :post, checks_path, notify: "1" # what the scheduled check does
    expect(page).to have_content("sent an alert by Telegram")
    expect(TelegramBot.sender.deliveries.last).to include(to: "9001")
    expect(page).to have_css("svg.chart .line.pool")
    expect(page).to have_content("Set heater to")

    visit edit_pool_path
    # Test mode lives in a collapsed section; submit its forms directly.
    page.driver.submit :post, forecast_snapshots_path, source: "live"
    page.driver.submit :patch, test_mode_path, snapshot_id: ForecastSnapshot.last.id
    expect(page).to have_content("Test mode on")
    expect(page).to have_content("No alerts are sent")
    click_button "Back to live"
    expect(page).to have_content("Test mode off")

    click_link "Dashboard"
    fill_in "Measured", with: "86"
    click_button "Log it"
    expect(page).to have_content("Logged the water at 86°F")

    click_link "Lab"
    expect(page).to have_content("Planner lab")
  end

  it "explains on the sign-in page that sign-up is closed" do
    create(:user)
    visit new_session_path
    expect(page).to have_content("New accounts are closed")
  end
end
