require "rails_helper"

RSpec.describe Geocoder do
  subject(:geocoder) { described_class.new }

  let(:brighton) do
    { lat: "43.1159044", lon: "-77.5619757", display_name: "14618, Town of Brighton, Monroe County, New York, United States",
      address: { postcode: "14618", town: "Town of Brighton", state: "New York" } }
  end

  it "treats 5 digits as a US ZIP code" do
    stub = stub_request(:get, "https://nominatim.openstreetmap.org/search")
      .with(query: hash_including("postalcode" => "14618", "country" => "us"), headers: { "User-Agent" => /AutoPoolTemp/ })
      .to_return(body: [ brighton ].to_json)
    expect(geocoder.search("14618")).to eq([ Geocoder::Place.new("14618, Town of Brighton, New York", 43.1159, -77.56198) ])
    expect(stub).to have_been_requested
  end

  it "searches anything else as free text" do
    stub_request(:get, "https://nominatim.openstreetmap.org/search").with(query: hash_including("q" => "Brighton, NY"))
      .to_return(body: [ brighton ].to_json)
    expect(geocoder.search("Brighton, NY").first.latitude).to eq(43.1159)
  end

  it "returns nothing for a blank query" do
    expect(geocoder.search("  ")).to eq([])
  end

  it "names a coordinate" do
    stub_request(:get, "https://nominatim.openstreetmap.org/reverse").with(query: hash_including("lat" => "43.12"))
      .to_return(body: brighton.to_json)
    expect(geocoder.reverse(43.12, -77.56).name).to eq("14618, Town of Brighton, New York")
  end

  it "returns nil when a coordinate can't be named" do
    stub_request(:get, %r{nominatim.openstreetmap.org/reverse}).to_return(body: { error: "Unable to geocode" }.to_json)
    expect(geocoder.reverse(0, 0)).to be_nil
  end

  it "raises on HTTP and network errors" do
    stub_request(:get, %r{nominatim}).to_return(status: 503)
    expect { geocoder.search("14618") }.to raise_error(Geocoder::Error, /503/)
    stub_request(:get, %r{nominatim}).to_raise(SocketError.new("offline"))
    expect { geocoder.search("14618") }.to raise_error(Geocoder::Error, /offline/)
  end
end
