require "rails_helper"

RSpec.describe ApplicationHelper do
  it "formats degrees" do
    expect(helper.degrees(90.6)).to eq("91°F")
    expect(helper.degrees(nil)).to eq("—")
  end

  it "formats times in the pool's zone" do
    pool = build(:pool, time_zone: "America/Chicago")
    expect(helper.local_time(Time.utc(2026, 10, 1, 12), pool)).to eq("Thu Oct 1, 7:00 am")
    expect(helper.local_time(nil, pool)).to eq("never")
  end

  it "explains where the setpoint came from" do
    expect(helper.setpoint_source_label("user_reported")).to eq("you reported it")
    expect(helper.setpoint_source_label(nil)).to eq("not yet known")
  end
end
