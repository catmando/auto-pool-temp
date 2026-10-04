require "rails_helper"

RSpec.describe PoolPhysics do
  subject(:physics) { described_class.new(heat_rate: 3, cool_rate: 2) }

  it "heats toward a higher setting at the heat rate, stopping there" do
    expect(physics.advance(80, 90, 24)).to eq(83)
    expect(physics.advance(89, 90, 24)).to eq(90)
  end

  it "cools toward a lower setting at the cool rate, stopping there" do
    expect(physics.advance(90, 80, 24)).to eq(88)
    expect(physics.advance(81, 80, 24)).to eq(80)
  end

  it "does nothing without a setting or time" do
    expect(physics.advance(85, nil, 24)).to eq(85)
    expect(physics.advance(85, 90, 0)).to eq(85)
  end
end
