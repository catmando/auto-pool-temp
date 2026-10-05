require "rails_helper"

RSpec.describe "Pool cover" do
  let(:pool) { create(:pool, :telegram, has_cover: true, cover_on: true, assumed_setpoint: 90) }

  before { sign_in_as(pool.user) }

  it "shows the recommended cover setting on the dashboard, and records a change" do
    get root_path
    expect(response.body).to match(%r{<dt>Pool cover</dt><dd>(On|Off)</dd>})
    patch cover_path, params: { on: "0" }
    expect(pool.reload.cover_on).to be false
    expect(flash[:notice]).to eq("Got it, the cover is off.")
  end

  it "hides the cover for pools without one" do
    pool.update!(has_cover: false)
    get root_path
    expect(response.body).not_to include("Pool cover</dt>")
  end

  it "has the cover checkbox and cooling factor on Settings" do
    get edit_pool_path
    expect(response.body).to include("I have a pool cover", "Cooling factor")
    patch pool_path(format: :json), params: { pool: { has_cover: "0", cooling_factor: "1.5" } }
    expect(pool.reload).to have_attributes(has_cover: false, cooling_factor: 1.5)
  end
end
