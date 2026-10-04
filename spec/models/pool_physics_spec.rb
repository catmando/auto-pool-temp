require "rails_helper"

RSpec.describe PoolPhysics do
  subject(:physics) { described_class.new(heat_rate: 2) }

  # Covered water at 100°F with 35°F air loses 3°F/day = 0.125°F/hour.
  describe "#step (one hour)" do
    it "heats toward the setting while the pump runs, stopping there" do
      expect(physics.step(80, 90, pump_fraction: 1.0, air: 80)).to be_within(1e-9).of(82)
      expect(physics.step(89, 90, pump_fraction: 1.0, air: 80)).to eq(90)
    end

    it "holds the setting against heat loss while the pump runs" do
      expect(physics.step(90, 90, pump_fraction: 1.0, air: 35)).to eq(90)
    end

    it "loses heat to cold air when the setting is lower" do
      expect(physics.step(100, 80, pump_fraction: 1.0, air: 35)).to be_within(1e-9).of(99.875)
    end

    it "can't heat with the pump off, and loses heat even below the setting" do
      expect(physics.step(100, 105, pump_fraction: 0.0, air: 35)).to be_within(1e-9).of(99.875)
    end

    it "loses heat faster with the cover off" do
      expect(physics.step(100, 80, pump_fraction: 0.0, air: 35, cover_on: false)).to be_within(1e-9).of(99.75)
    end

    it "warms in hot air" do
      expect(physics.step(80, 70, pump_fraction: 0.0, air: 90)).to be_within(1e-9).of(80.125)
    end

    it "uses only part of the heater for a partial pump hour" do
      expect(physics.step(80, 90, pump_fraction: 0.5, air: 80)).to be_within(1e-9).of(81)
    end

    it "never heats without a setting" do
      expect(physics.step(80, nil, pump_fraction: 1.0, air: 80)).to eq(80)
    end
  end

  describe "#advance" do
    let(:zone) { ActiveSupport::TimeZone["America/New_York"] }
    let(:air) { Pool::SteadyAir.new(65) }
    subject(:physics) { described_class.new(heat_rate: 2, pump: PumpSchedule.new([ %w[04:00 10:00] ], time_zone: zone.name)) }

    it "heats only during pump hours and loses heat the rest of the day" do
      midnight = zone.local(2026, 10, 5)
      loss_per_hour = PoolEnvironment::COVERED_LOSS * (95 - 65) / 24.0
      # Midnight-4am loses a little; 4-10am heats back to 95; then loses until midnight (14 h).
      after = physics.advance(94, 95, from: midnight, to: midnight + 24.hours, air: air)
      expect(after).to be_within(0.02).of(95 - loss_per_hour * 14)
    end

    it "does nothing without time" do
      t = zone.local(2026, 10, 5, 5)
      expect(physics.advance(85, 95, from: t, to: t, air: air)).to eq(85)
    end
  end
end
