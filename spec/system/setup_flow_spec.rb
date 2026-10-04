require "rails_helper"

RSpec.describe "Setting up the app" do
  it "goes from sign-up through settings and phone confirmation to a first alert" do
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

    expect(page).to have_content("We texted a code to +15125550100")
    expect(page).to have_content("Not confirmed yet")
    fill_in "Code", with: Sms.sender.last_body[/\d{6}/]
    click_button "Confirm"
    expect(page).to have_content("Phone number confirmed.")
    expect(page).to have_content("Confirmed ✓")

    click_link "Dashboard"
    expect(page).to have_content("not yet known")
    click_button "Check & alert if needed"

    expect(page).to have_content("Recommended 91°F and sent an alert by Text message (Twilio).")
    expect(page).to have_content("assumed: you followed the last alert")
    expect(page).to have_css("svg.chart")
    expect(Sms.sender.deliveries.last[:to]).to eq("+15125550100")

    fill_in "Actually set to", with: "86"
    click_button "Update"
    expect(page).to have_content("the heater is set to 86°F")

    click_link "Messages"
    expect(page).to have_content("set the heater to 91°F")
  end

  it "connects Telegram with a one-time link" do
    allow(TelegramBot).to receive(:configured?).and_return(true)
    user = create(:user)
    user.pool.update!(latitude: 30.27, longitude: -97.74, time_zone: "America/Chicago")
    sign_in_as(user)

    visit edit_pool_path
    select "Telegram", from: "Send alerts by"
    click_button "Save settings"
    expect(page).to have_content("Confirm where alerts should go")

    click_button "Connect Telegram"
    link = find_link("Open Telegram to connect")[:href]
    token = link[/start=(.+)\z/, 1]

    # What Telegram does when the user taps Start:
    InboundMessage.handle(channel: "telegram", from: "9001", body: "/start #{token}")
    expect(TelegramBot.sender.last_body).to start_with("Connected!")

    visit edit_pool_path
    expect(page).to have_content("Connected ✓")
    expect(user.pool.reload).to be_notifiable
  end
end
