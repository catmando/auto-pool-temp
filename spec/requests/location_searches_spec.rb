require "rails_helper"

RSpec.describe "Location search (map)" do
  let(:pool) { create(:pool) }

  before { sign_in_as(pool.user) }

  it "returns matching places as JSON" do
    Geocoder.default.places = [ Geocoder::Place.new("14618, Town of Brighton, New York", 43.1159, -77.562) ]
    post location_search_path, params: { query: "14618" }, as: :json
    expect(response.parsed_body).to eq([ { "name" => "14618, Town of Brighton, New York", "latitude" => 43.1159, "longitude" => -77.562 } ])
  end

  it "returns an empty list when nothing matches" do
    post location_search_path, params: { query: "zzz" }, as: :json
    expect(response.parsed_body).to eq([])
  end

  it "reports lookup errors" do
    Geocoder.default.error = Geocoder::Error.new("location lookup failed (503)")
    post location_search_path, params: { query: "14618" }, as: :json
    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body["error"]).to include("503")
  end
end
