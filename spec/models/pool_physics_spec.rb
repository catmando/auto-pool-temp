require "rails_helper"

RSpec.describe PoolPhysics do
  subject(:physics) { described_class.new(heat_rate: 2, cool_rate: 0.1) }

  describe "#step (one hour)" do
    it "heats toward a higher setting while the pump runs, stopping there" do
      expect(physics.step(80, 90, 1.0)).to eq(82)
      expect(physics.step(89, 90, 1.0)).to eq(90)
    end

    it "cools toward a lower setting while the pump runs (heater off), stopping there" do
      expect(physics.step(90, 80, 1.0)).to be_within(1e-9).of(89.9)
      expect(physics.step(80.05, 80, 1.0)).to eq(80)
    end

    it "can't heat with the pump off, and cools even below the setting" do
      expect(physics.step(80, 90, 0.0)).to be_within(1e-9).of(79.9)
      expect(physics.step(90, 90, 0.0)).to be_within(1e-9).of(89.9)
    end

    it "splits an hour the pump runs part of" do
      expect(physics.step(80, 90, 0.5)).to be_within(1e-9).of(80 + 1 - 0.05)
    end

    it "does nothing without a setting" do
      expect(physics.step(85, nil, 1.0)).to eq(85)
    end
  end

  describe "#advance" do
    let(:zone) { ActiveSupport::TimeZone["America/New_York"] }
    let(:pump) { PumpSchedule.new([ %w[04:00 10:00] ], time_zone: zone.name) }
    subject(:physics) { described_class.new(heat_rate: 2, cool_rate: 0.1, pump: pump) }

    it "heats only during pump hours and cools the rest of the day" do
      midnight = zone.local(2026, 10, 5)
      # 0-4am: cools 0.4; 4-10am: heats to the setting; 10am-midnight: cools 1.4
      expect(physics.advance(85, 95, from: midnight, to: midnight + 24.hours)).to be_within(1e-6).of(93.6)
    end

    it "handles a partial hour" do
      four = zone.local(2026, 10, 5, 4)
      expect(physics.advance(85, 95, from: four, to: four + 30.minutes)).to be_within(1e-6).of(86)
    end

    it "does nothing without time or a setting" do
      t = zone.local(2026, 10, 5, 5)
      expect(physics.advance(85, 95, from: t, to: t)).to eq(85)
      expect(physics.advance(85, nil, from: t, to: t + 5.hours)).to eq(85)
    end
  end
end
