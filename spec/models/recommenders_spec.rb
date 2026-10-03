require "rails_helper"

RSpec.describe Recommenders do
  it "looks strategies up by key" do
    expect(described_class.for("lookahead")).to eq(Recommenders::Lookahead)
    expect(described_class.for(:linear)).to eq(Recommenders::Linear)
  end

  it "raises for unknown strategies" do
    expect { described_class.for("magic") }.to raise_error(ArgumentError, /magic/)
  end

  it "gives every strategy a label and description" do
    described_class.registry.each_value do |klass|
      expect(klass).to be < Recommenders::Base
      expect(klass.label).to be_present
      expect(klass.description).to be_present
    end
  end
end
