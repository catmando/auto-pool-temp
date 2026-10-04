require "rails_helper"

RSpec.describe "Confirming a location" do
  let(:pool) { create(:pool, :unlocated, time_zone: "UTC") }

  before { sign_in_as(pool.user) }

  it "saves a searched place with its name and time zone" do
    patch location_path, params: { latitude: "43.1159", longitude: "-77.562", name: "14618, Town of Brighton, New York" }
    expect(response).to redirect_to(edit_pool_path)
    expect(flash[:notice]).to eq("Location set to 14618, Town of Brighton, New York.")
    expect(pool.reload).to have_attributes(latitude: 43.1159, longitude: -77.562, time_zone: "America/New_York",
                                           location_name: "14618, Town of Brighton, New York")
  end

  it "names a spot picked on the map" do
    patch location_path, params: { latitude: "43.12", longitude: "-77.56", name: "" }
    expect(pool.reload.location_name).to eq("14618, Town of Brighton, New York")
  end

  it "falls back to coordinates when the name lookup fails" do
    Geocoder.default.error = Geocoder::Error.new("down")
    patch location_path, params: { latitude: "43.12", longitude: "-77.56" }
    expect(pool.reload.location_name).to eq("43.12, -77.56")
  end

  it "keeps the time zone when its lookup fails" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    patch location_path, params: { latitude: "43.12", longitude: "-77.56", name: "Here" }
    expect(pool.reload).to have_attributes(location_name: "Here", time_zone: "UTC")
  end

  it "rejects a missing or bad spot" do
    patch location_path, params: { latitude: "", longitude: "-77.56" }
    expect(flash[:alert]).to include("Pick a spot")
    patch location_path, params: { latitude: "200", longitude: "0" }
    expect(pool.reload).not_to be_located
  end
end
