require "rails_helper"

RSpec.describe User do
  subject { build(:user) }

  it { is_expected.to have_many(:sessions).dependent(:destroy) }
  it { is_expected.to have_one(:pool).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:email_address) }
  it { is_expected.to validate_length_of(:password).is_at_least(8) }

  it "normalizes email addresses" do
    expect(create(:user, email_address: "  Me@Example.COM ").email_address).to eq("me@example.com")
  end

  it "rejects malformed email addresses" do
    expect(build(:user, email_address: "nope")).not_to be_valid
  end

  it "gets a pool with default settings when created" do
    pool = create(:user).pool
    expect(pool).to be_persisted
    expect(pool).to have_attributes(hot_air_temp: 95, hot_pool_temp: 80, cold_air_temp: 35, cold_pool_temp: 102,
                                    heat_rate_per_day: 3, cool_rate_per_day: 2, checks_per_day: 2,
                                    strategy: "lookahead", assumed_setpoint: nil)
  end
end
