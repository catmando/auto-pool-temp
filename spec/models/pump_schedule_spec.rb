require "rails_helper"

RSpec.describe PumpSchedule do
  let(:zone) { ActiveSupport::TimeZone["America/New_York"] }
  subject(:pump) { described_class.new([ %w[04:00 10:00], %w[16:00 22:00] ], time_zone: zone.name) }

  it "knows when the pump runs, in local time" do
    expect(pump.on_at?(zone.local(2026, 10, 5, 4))).to be true
    expect(pump.on_at?(zone.local(2026, 10, 5, 9, 59))).to be true
    expect(pump.on_at?(zone.local(2026, 10, 5, 10))).to be false
    expect(pump.on_at?(zone.local(2026, 10, 5, 21))).to be true
    expect(pump.on_at?(zone.local(2026, 10, 5, 23))).to be false
  end

  it "gives the share of an hour the pump runs" do
    expect(pump.on_fraction(zone.local(2026, 10, 5, 5))).to eq(1.0)
    expect(pump.on_fraction(zone.local(2026, 10, 5, 12))).to eq(0.0)
    half = described_class.new([ %w[06:30 20:00] ], time_zone: zone.name)
    expect(half.on_fraction(zone.local(2026, 10, 5, 6))).to eq(0.5)
  end

  it "handles a window past midnight" do
    night = described_class.new([ %w[22:00 02:00] ], time_zone: zone.name)
    expect(night.on_at?(zone.local(2026, 10, 5, 23))).to be true
    expect(night.on_at?(zone.local(2026, 10, 5, 1))).to be true
    expect(night.on_at?(zone.local(2026, 10, 5, 3))).to be false
  end

  it "skips blank or bad windows, and runs always with none" do
    one = described_class.new([ %w[06:00 20:00], [ "", "" ], %w[25:00 26:00] ])
    expect(one.windows).to eq([ [ 360, 1200 ] ])
    expect(described_class.always_on).to be_always_on
    expect(described_class.always_on.on_fraction(Time.current)).to eq(1.0)
  end

  it "describes itself and counts hours" do
    expect(pump.describe).to eq("4am–10am and 4pm–10pm")
    expect(pump.hours_per_day).to eq(12)
  end
end
