require "rails_helper"

# The party blocks' browser behavior (Stimulus): needs a real browser.
RSpec.describe "Planning a pool party", js: true do
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 91) }
  let(:day) { (Time.current.in_time_zone(pool.zone) + 2.days).to_date }

  before do
    allow(TelegramBot).to receive(:configured?).and_return(true)
    sign_in_as(pool.user)
  end

  def set_date(field, date) = page.execute_script(
    "const f = document.querySelector('#{field}'); f.value = '#{date.iso8601}'; f.dispatchEvent(new Event('change', { bubbles: true }))"
  )

  it "fills the end date from the start date, then shows the outlook and a new blank block" do
    visit root_path
    within("#party") do
      set_date("[data-party-target=startDate]", day)
      expect(find("[data-party-target=endDate]").value).to eq(day.iso8601)
      select "+7°F", from: "How much warmer"
      click_button "Plan the party"
    end
    expect(page).to have_content("Pool party planned for")
    within("#party") do
      expect(page).to have_css(".party-block.saved", count: 1)
      expect(page).to have_content("Your pool target is")
      expect(page).to have_button("Delete")
      expect(page).to have_css(".party-block:not(.saved)", count: 1) # the new blank block
    end
  end

  it "switches a saved party back to 'Plan the party' while it's being edited, hiding the blank block" do
    pool.pool_parties.build.assign_from_form(start_date: day.iso8601, boost: 5).save!
    visit root_path
    saved = find(".party-block.saved")
    expect(saved).to have_no_button("Plan the party")
    saved.select "+9°F", from: "How much warmer"
    expect(saved).to have_button("Plan the party")
    expect(saved).to have_no_button("Delete")
    expect(page).to have_no_css("[data-parties-target=blank] .party-block", visible: true)
    saved.click_button "Plan the party"
    expect(page).to have_content("Pool party planned for")
    expect(pool.pool_parties.first.reload.boost).to eq(9)
  end

  it "lists parties in date order" do
    pool.pool_parties.build.assign_from_form(start_date: (day + 5).iso8601, boost: 2).save!
    pool.pool_parties.build.assign_from_form(start_date: day.iso8601, boost: 3).save!
    visit root_path
    labels = all(".party-outlook strong", text: /until/).map(&:text)
    expect(labels.first).to start_with(day.strftime("%a %b %-d"))
  end
end
