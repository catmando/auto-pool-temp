require "rails_helper"

RSpec.describe PoolLog do
  let(:pool) { create(:pool, assumed_setpoint: 90) }

  it { is_expected.to belong_to(:pool) }
  it { is_expected.to validate_inclusion_of(:kind).in_array(%w[water_reading setting_confirmed]) }
  it { is_expected.to validate_inclusion_of(:source).in_array(%w[web sms telegram]) }

  it "logs a reading with the model's estimate, and leaves the model alone" do
    log = described_class.water_reading!(pool, 86, source: "web")
    expect(log).to have_attributes(water_temp: 86, expected_water_temp: 90)
    expect(pool.reload).to have_attributes(water_temp: nil, assumed_setpoint: 90)
  end

  it "logs a confirmation and treats the setting as made at that moment" do
    at = 2.hours.from_now
    log = described_class.confirm_setting!(pool, water_temp: 88, source: "telegram", at: at)
    expect(log).to have_attributes(kind: "setting_confirmed", setpoint: 90, water_temp: 88, logged_at: at)
    expect(pool.reload).to have_attributes(setpoint_source: "confirmed", setpoint_updated_at: at)
  end

  it "rejects impossible readings" do
    expect(pool.pool_logs.build(kind: "water_reading", source: "web", logged_at: Time.current, water_temp: 200)).not_to be_valid
  end
end
