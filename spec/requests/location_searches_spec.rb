require "rails_helper"

RSpec.describe "Location search" do
  let(:pool) { create(:pool) }

  before { sign_in_as(pool.user) }

  it "lists matching places as pickable buttons" do
    Weather.provider.places = [ Weather::OpenMeteo::Place.new("Austin, Texas, US", 30.27, -97.74, "America/Chicago") ]
    post location_search_path, params: { query: "Austin" }
    expect(response.body).to include("location_results", "Austin, Texas, US", "location#pick",
                                     'data-location-time-zone-param="America/Chicago"')
  end

  it "says when nothing matches" do
    post location_search_path, params: { query: "zzz" }
    expect(response.body).to include("No places found")
  end

  it "shows provider errors" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    post location_search_path, params: { query: "Austin" }
    expect(response.body).to include("down")
  end
end
