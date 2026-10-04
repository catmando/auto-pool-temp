require "rails_helper"

RSpec.describe Weather::OpenMeteo do
  subject(:client) { described_class.new }

  describe "#forecast" do
    let(:body) do
      { timezone: "America/Chicago",
        hourly: { time: [ 1_790_000_000, 1_790_003_600, 1_790_007_200 ], temperature_2m: [ 70.1, nil, 72.5 ] } }.to_json
    end

    before do
      stub_request(:get, %r{api.open-meteo.com/v1/forecast}).to_return(status: 200, body: body)
    end

    it "requests hourly Fahrenheit data for the location" do
      client.forecast(latitude: 30.27, longitude: -97.74, days: 7)
      expect(WebMock).to have_requested(:get, "https://api.open-meteo.com/v1/forecast")
        .with(query: hash_including("latitude" => "30.27", "longitude" => "-97.74", "hourly" => "temperature_2m",
                                    "temperature_unit" => "fahrenheit", "forecast_days" => "7", "timezone" => "auto"))
    end

    it "builds a forecast, skipping missing temperatures" do
      forecast = client.forecast(latitude: 1, longitude: 2)
      expect(forecast.points.map(&:temp)).to eq([ 70.1, 72.5 ])
      expect(forecast.start_time).to eq(Time.zone.at(1_790_000_000))
      expect(forecast).to have_attributes(time_zone: "America/Chicago", source: "open-meteo")
    end

    it "caps forecast days at 16" do
      client.forecast(latitude: 1, longitude: 2, days: 40)
      expect(WebMock).to have_requested(:get, /forecast_days=16/)
    end

    it "raises on HTTP errors" do
      stub_request(:get, %r{api.open-meteo.com}).to_return(status: 500, body: "boom")
      expect { client.forecast(latitude: 1, longitude: 2) }.to raise_error(described_class::Error, /500/)
    end

    it "raises on network failures" do
      stub_request(:get, %r{api.open-meteo.com}).to_raise(SocketError.new("no route"))
      expect { client.forecast(latitude: 1, longitude: 2) }.to raise_error(described_class::Error, /no route/)
    end

    it "raises when no temperatures come back" do
      stub_request(:get, %r{api.open-meteo.com}).to_return(body: { hourly: { time: [ 1 ], temperature_2m: [ nil ] } }.to_json)
      expect { client.forecast(latitude: 1, longitude: 2) }.to raise_error(described_class::Error, /no temperatures/)
    end
  end

  describe "#search" do
    it "returns places with labels and time zones" do
      stub_request(:get, %r{geocoding-api.open-meteo.com/v1/search}).with(query: hash_including("name" => "Austin"))
        .to_return(body: { results: [ { name: "Austin", admin1: "Texas", country_code: "US",
                                        latitude: 30.27, longitude: -97.74, timezone: "America/Chicago" } ] }.to_json)
      expect(client.search("Austin")).to eq([
        described_class::Place.new("Austin, Texas, US", 30.27, -97.74, "America/Chicago")
      ])
    end

    it "returns an empty list when nothing matches" do
      stub_request(:get, %r{geocoding-api.open-meteo.com}).to_return(body: "{}")
      expect(client.search("zzz")).to eq([])
    end
  end
end

RSpec.describe Weather::OpenMeteo, "#time_zone_for" do
  it "asks Open-Meteo for the location's time zone" do
    stub_request(:get, %r{api.open-meteo.com/v1/forecast}).with(query: hash_including("timezone" => "auto"))
      .to_return(body: { timezone: "America/New_York" }.to_json)
    expect(described_class.new.time_zone_for(latitude: 43.1, longitude: -77.6)).to eq("America/New_York")
  end
end
