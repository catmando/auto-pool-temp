require "rails_helper"

# The party blocks' browser behavior (Stimulus): needs a real browser.
RSpec.describe "Planning a pool party", js: true do
  # UTC to match the fake forecast (the app adopts the forecast's time zone when it plans).
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 91, time_zone: "UTC") }
  let(:day) { (Time.current.in_time_zone(pool.zone) + 2.days).to_date }

  before do
    allow(TelegramBot).to receive(:configured?).and_return(true)
    sign_in_as(pool.user)
  end

  # Visit the dashboard and wait until every party block's JavaScript is running.
  def visit_dashboard
    visit root_path
    expect(page).to have_no_css("[data-controller=party]:not([data-party-ready])")
  end

  def set_date(field, date) = page.execute_script(
    "const f = document.querySelector('#{field}'); f.value = '#{date.respond_to?(:iso8601) ? date.iso8601 : date}'; f.dispatchEvent(new Event('change', { bubbles: true }))"
  )

  it "greys out Plan the party until a date is picked" do
    visit_dashboard
    within("#party") do
      expect(page).to have_button("Plan the party", disabled: true)
      set_date("[data-party-target=startDate]", day)
      expect(page).to have_button("Plan the party", disabled: false)
      set_date("[data-party-target=startDate]", "")
      expect(page).to have_button("Plan the party", disabled: true)
    end
  end

  describe "the Until date tracks the start date" do
    def start_date(d) = set_date("#party [data-party-target=startDate]", d)
    def end_date = first("#party [data-party-target=endDate]").value
    def set_end(d) = set_date("#party [data-party-target=endDate]", d)

    # The owner's bug (2026-10-05): after moving the start later and then back
    # earlier, Until stayed on the later date.
    it "follows the start date forward and back" do
      visit_dashboard
      start_date(day)
      expect(end_date).to eq(day.iso8601)
      start_date(day + 3)
      expect(end_date).to eq((day + 3).iso8601)
      start_date(day + 1)
      expect(end_date).to eq((day + 1).iso8601)
    end

    it "keeps the party's length when the start moves" do
      visit_dashboard
      start_date(day)
      set_end(day + 2) # a three-day party
      start_date(day + 5)
      expect(end_date).to eq((day + 7).iso8601)
      start_date(day + 1)
      expect(end_date).to eq((day + 3).iso8601)
    end

    it "keeps a planned party's length too" do
      pool.pool_parties.build.assign_from_form(start_date: day.iso8601, end_date: (day + 1).iso8601, boost: 5).save!
      visit_dashboard
      within(".party-block.saved") do
        set_date(".party-block.saved [data-party-target=startDate]", day + 4)
        expect(find("[data-party-target=endDate]").value).to eq((day + 5).iso8601)
      end
    end
  end

  describe "Until can't be before the start" do
    def set_field(selector, value) = page.execute_script(
      "const f = document.querySelector('#{selector}'); f.value = '#{value}'; f.dispatchEvent(new Event('change', { bubbles: true }))"
    )
    let(:blank) { "[data-parties-target=blank]" }

    it "won't offer Until dates before the start date" do
      visit_dashboard
      set_field("#{blank} [data-party-target=startDate]", day.iso8601)
      expect(find("#{blank} [data-party-target=endDate]")[:min]).to eq(day.iso8601)
    end

    it "flags an Until date before the start and keeps Plan the party greyed out" do
      visit_dashboard
      set_field("#{blank} [data-party-target=startDate]", day.iso8601)
      set_field("#{blank} [data-party-target=endDate]", (day - 1).iso8601)
      within(blank) do
        expect(page).to have_content("The party has to end after it starts.")
        expect(page).to have_button("Plan the party", disabled: true)
      end
      set_field("#{blank} [data-party-target=endDate]", (day + 1).iso8601)
      within(blank) do
        expect(page).to have_no_content("The party has to end after it starts.")
        expect(page).to have_button("Plan the party", disabled: false)
      end
    end

    it "flags a same-day Until time at or before the start time" do
      visit_dashboard
      set_field("#{blank} [data-party-target=startDate]", day.iso8601)
      set_field("#{blank} [data-party-target=startTime]", "15:00")
      set_field("#{blank} [data-party-target=endTime]", "14:00")
      within(blank) { expect(page).to have_button("Plan the party", disabled: true) }
      set_field("#{blank} [data-party-target=endTime]", "18:00")
      within(blank) { expect(page).to have_button("Plan the party", disabled: false) }
    end
  end

  it "fills the end date from the start date, then shows the outlook and a new blank block" do
    visit_dashboard
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
      expect(page).to have_css("button.danger", text: "Delete")
      expect(page).to have_no_button("Plan the party", count: 2)
      expect(page).to have_css(".party-block:not(.saved)", count: 1) # the new blank block
    end
  end

  it "switches a saved party back to 'Plan the party' while it's being edited, hiding the blank block" do
    pool.pool_parties.build.assign_from_form(start_date: day.iso8601, boost: 5).save!
    visit_dashboard
    saved = find(".party-block.saved")
    expect(saved).to have_no_button("Plan the party")
    saved.select "+9°F", from: "How much warmer"
    expect(saved).to have_button("Plan the party")
    expect(saved).to have_no_css("button.danger", text: "Delete")
    expect(page).to have_no_css("[data-parties-target=blank] .party-block", visible: true)
    saved.click_button "Plan the party"
    expect(page).to have_content("Pool party planned for")
    expect(pool.pool_parties.first.reload.boost).to eq(9)
  end

it "deletes a planned party with the red Delete button" do
  pool.pool_parties.build.assign_from_form(start_date: day.iso8601, boost: 5).save!
  visit root_path
  find(".party-block.saved").click_button "Delete"
  expect(page).to have_content("Pool party removed.")
  expect(pool.pool_parties.reload).to be_empty
end

it "lists parties in date order" do
    pool.pool_parties.build.assign_from_form(start_date: (day + 5).iso8601, boost: 2).save!
    pool.pool_parties.build.assign_from_form(start_date: day.iso8601, boost: 3).save!
    visit_dashboard
    labels = all(".party-outlook strong", text: /until/).map(&:text)
    expect(labels.first).to start_with(day.strftime("%a %b %-d"))
  end
end
