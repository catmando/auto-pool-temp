require "rails_helper"

RSpec.describe WeatherTrend do
  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }

  def trend(days: 6, start_hour: 0, &air)
    start = zone.local(2026, 10, 5, start_hour)
    rows = (0...(days * 24 - start_hour)).map { |h| { "t" => (start + h.hours).iso8601, "air" => air.call(h + start_hour) } }
    described_class.for(rows, zone: zone)
  end

  it "is nil when the coming days are within 5°F of today's average" do
    expect(trend { |h| 60 + (h / 24) }).to be_nil # +1°F a day: 4°F by day 4
  end

  it "spots warmer or cooler days ahead" do
    expect(trend { |h| h < 72 ? 60 : 66 }).to eq(:warmer)
    expect(trend { |h| h < 72 ? 60 : 54 }).to eq(:cooler)
  end

  it "looks at most 4 days ahead" do
    expect(trend { |h| h < 5 * 24 ? 60 : 80 }).to be_nil
  end

  it "uses daily averages, not the daily swing" do
    expect(trend { |h| 60 + 12 * Math.sin(2 * Math::PI * h / 24) }).to be_nil
  end

  it "works from a partial first day" do
    expect(trend(start_hour: 17) { |h| h < 48 ? 60 : 70 }).to eq(:warmer)
  end

  it "is nil without enough data" do
    expect(described_class.for([], zone: zone)).to be_nil
  end
end
