require "rails_helper"

RSpec.describe Weather::Forecast do
  let(:t0) { Time.utc(2026, 10, 1, 0) }

  def point(hours, temp) = described_class::Point.new(t0 + hours.hours, temp)

  describe ".new" do
    it "sorts points by time" do
      forecast = described_class.new([ point(2, 70), point(0, 50), point(1, 60) ])
      expect(forecast.points.map(&:temp)).to eq([ 50, 60, 70 ])
    end

    it "rejects an empty series" do
      expect { described_class.new([]) }.to raise_error(ArgumentError, /no data/)
    end
  end

  describe "#temp_at" do
    subject(:forecast) { described_class.new([ point(0, 50), point(2, 70) ]) }

    it "returns exact values at sample times" do
      expect(forecast.temp_at(t0 + 2.hours)).to eq(70)
    end

    it "interpolates linearly between samples" do
      expect(forecast.temp_at(t0 + 30.minutes)).to be_within(0.001).of(55)
    end

    it "clamps before the start and after the end" do
      expect(forecast.temp_at(t0 - 5.hours)).to eq(50)
      expect(forecast.temp_at(t0 + 5.hours)).to eq(70)
    end
  end

  describe "#smoothed" do
    it "averages over a centered window, removing the daily swing" do
      forecast = described_class.new((0..96).map { |h| point(h, 60 + 10 * Math.sin(2 * Math::PI * h / 24)) })
      smooth = forecast.smoothed(window_hours: 24)
      expect(smooth.temp_at(t0 + 48.hours)).to be_within(0.5).of(60)
    end

    it "shrinks the window at the edges" do
      forecast = described_class.new([ point(0, 40), point(1, 60), point(30, 100) ])
      expect(forecast.smoothed(window_hours: 24).points.first.temp).to eq(50)
    end

    it "keeps metadata" do
      forecast = described_class.new([ point(0, 40) ], time_zone: "UTC", source: "x")
      expect(forecast.smoothed).to have_attributes(time_zone: "UTC", source: "x")
    end
  end

  describe ".from_daily" do
    let(:days) do
      [ { date: Date.new(2026, 10, 1), high: 80, low: 60 },
        { date: Date.new(2026, 10, 2), high: 90, low: 70 } ]
    end
    subject(:forecast) { described_class.from_daily(days, time_zone: "America/Chicago") }
    let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }

    it "puts the low at 3 AM and the high at 3 PM local time" do
      expect(forecast.temp_at(zone.local(2026, 10, 1, 3))).to eq(60)
      expect(forecast.temp_at(zone.local(2026, 10, 1, 15))).to eq(80)
      expect(forecast.temp_at(zone.local(2026, 10, 2, 3))).to eq(70)
      expect(forecast.temp_at(zone.local(2026, 10, 2, 15))).to eq(90)
    end

    it "fills hourly points with a smooth curve between" do
      expect(forecast.temp_at(zone.local(2026, 10, 1, 9))).to be_within(0.01).of(70)
      expect(forecast.temp_at(zone.local(2026, 10, 1, 4))).to be < 61
      expect(forecast.points.map(&:time).each_cons(2).map { |a, b| b - a }.uniq).to eq([ 3600.0 ])
    end

    it "spans from the first low to the last high" do
      expect(forecast.start_time).to eq(zone.local(2026, 10, 1, 3))
      expect(forecast.end_time).to eq(zone.local(2026, 10, 2, 15))
      expect(forecast.time_zone).to eq("America/Chicago")
    end

    it "rejects unknown time zones" do
      expect { described_class.from_daily(days, time_zone: "Mars/Base") }.to raise_error(ArgumentError)
    end
  end
end
