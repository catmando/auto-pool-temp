require "rails_helper"

RSpec.describe Pool do
  subject(:pool) { create(:pool) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:recommendations).dependent(:destroy) }
    it { is_expected.to have_many(:text_messages).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_numericality_of(:heat_rate_per_hour).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:cooling_factor).is_greater_than(0) }
    it { is_expected.to validate_inclusion_of(:checks_per_day).in_array([ 1, 2, 3 ]) }
    it { is_expected.to validate_numericality_of(:forecast_days).only_integer.is_in(1..16) }
    it { is_expected.to validate_numericality_of(:min_change).only_integer.is_greater_than_or_equal_to(1) }

    it "requires a registered strategy" do
      pool.strategy = "nope"
      expect(pool).not_to be_valid
    end

    it "requires distinct air anchors" do
      pool.cold_air_temp = pool.hot_air_temp
      expect(pool).not_to be_valid
      expect(pool.errors[:hot_air_temp]).to be_present
    end

    it "requires a known time zone" do
      pool.time_zone = "Nowhere/Land"
      expect(pool).not_to be_valid
    end

    it "bounds latitude and longitude" do
      pool.latitude = 91
      pool.longitude = 181
      expect(pool).not_to be_valid
      expect(pool.errors.attribute_names).to include(:latitude, :longitude)
    end

    it "bounds the assumed setpoint" do
      pool.assumed_setpoint = 150
      expect(pool).not_to be_valid
    end
  end

  describe "phone number normalization" do
    it "adds +1 to 10-digit US numbers" do
      expect(build(:pool, phone_number: "(512) 555-0100").phone_number).to eq("+15125550100")
    end

    it "keeps international numbers" do
      expect(build(:pool, phone_number: "+44 20 7946 0958").phone_number).to eq("+442079460958")
    end

    it "treats blank as nil" do
      expect(build(:pool, phone_number: "  ").phone_number).to be_nil
    end

    it "rejects numbers that are too short" do
      expect(build(:pool, phone_number: "12345")).not_to be_valid
    end
  end

  describe "#located?" do
    it { expect(build(:pool)).to be_located }
    it { expect(build(:pool, :unlocated)).not_to be_located }
  end

  describe "scheduling" do
    let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }

    it "maps checks per day to local hours" do
      expect(build(:pool, checks_per_day: 1).check_hours).to eq([ 7 ])
      expect(build(:pool, checks_per_day: 3).check_hours).to eq([ 7, 13, 19 ])
    end

    describe "#due?" do
      it "is due for a first check right away" do
        expect(pool.due?(zone.local(2026, 10, 1, 8, 5))).to be true
      end

      it "is due once a check time passes" do
        pool.update!(last_checked_at: zone.local(2026, 10, 1, 7, 5))
        expect(pool.due?(zone.local(2026, 10, 1, 16, 59))).to be false
        expect(pool.due?(zone.local(2026, 10, 1, 17, 5))).to be true
      end

      it "is not due twice for the same check time" do
        pool.update!(last_checked_at: zone.local(2026, 10, 1, 17, 5))
        expect(pool.due?(zone.local(2026, 10, 1, 20, 5))).to be false
      end

      it "catches up on a check missed while asleep" do
        pool.update!(last_checked_at: zone.local(2026, 9, 30, 17, 5))
        expect(pool.due?(zone.local(2026, 10, 1, 9, 30))).to be true
      end

      it "goes by the pool's time zone" do
        pool.update!(last_checked_at: zone.local(2026, 10, 1, 6, 0))
        expect(pool.due?(Time.utc(2026, 10, 1, 11, 59))).to be false # 6:59am Chicago
        expect(pool.due?(Time.utc(2026, 10, 1, 12, 5))).to be true   # 7:05am Chicago
      end

      it "is never due without a location" do
        expect(build(:pool, :unlocated).due?(zone.local(2026, 10, 1, 7, 5))).to be false
      end
    end

    describe "#last_scheduled_check_at" do
      it "finds the most recent check time, including yesterday's" do
        expect(pool.last_scheduled_check_at(zone.local(2026, 10, 1, 12))).to eq(zone.local(2026, 10, 1, 7))
        expect(pool.last_scheduled_check_at(zone.local(2026, 10, 1, 6))).to eq(zone.local(2026, 9, 30, 17))
      end
    end

    describe "#next_check_after" do
      it "finds the next check later today" do
        expect(pool.next_check_after(zone.local(2026, 10, 1, 9))).to eq(zone.local(2026, 10, 1, 17))
      end

      it "rolls over to tomorrow" do
        expect(pool.next_check_after(zone.local(2026, 10, 1, 17))).to eq(zone.local(2026, 10, 2, 7))
      end
    end
  end

  describe "#needs_change?" do
    it "is true when the setting is unknown" do
      expect(build(:pool, assumed_setpoint: nil).needs_change?(85)).to be true
    end

    it "respects the minimum change" do
      pool = build(:pool, assumed_setpoint: 85, min_change: 2)
      expect(pool.needs_change?(86)).to be false
      expect(pool.needs_change?(87)).to be true
      expect(pool.needs_change?(83)).to be true
    end
  end

  describe "#record_setpoint!" do
    it "stores the value, source, and time" do
      freeze_time do
        pool.record_setpoint!(84, source: "user_reported")
        expect(pool.reload).to have_attributes(assumed_setpoint: 84, setpoint_source: "user_reported",
                                               setpoint_updated_at: Time.current)
      end
    end
  end

  it "resolves its recommender class" do
    expect(build(:pool, strategy: "follow").recommender_class).to eq(Recommenders::Follow)
  end
end

RSpec.describe Pool, "alert delivery" do
  it { is_expected.to validate_inclusion_of(:notification_channel).in_array(%w[sms telegram]) }

  it "needs a confirmed phone for SMS" do
    expect(build(:pool)).to be_contact_verified
    expect(build(:pool, :unverified)).not_to be_contact_verified
    expect(build(:pool, phone_number: nil)).not_to be_phone_verified
  end

  it "needs a linked chat for Telegram" do
    expect(build(:pool, :telegram)).to be_contact_verified
    expect(build(:pool, notification_channel: "telegram")).not_to be_contact_verified
  end

  it "is notifiable only when enabled and confirmed" do
    expect(build(:pool)).to be_notifiable
    expect(build(:pool, notifications_enabled: false)).not_to be_notifiable
  end

  it "keeps verification when the phone doesn't change" do
    pool = create(:pool)
    pool.update!(name: "Renamed")
    expect(pool.reload).to be_phone_verified
  end
end

RSpec.describe Pool, "water temperature" do
  # Heats 2°F/h while the pump runs (4-10am, 4-10pm Chicago time); loses heat to
  # 65°F air the rest of the time (no cover, so the uncovered rate).
  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }
  let(:pool) { create(:pool, assumed_setpoint: 90, heat_rate_per_hour: 2) }
  let(:air) { Pool::SteadyAir.new(65) }

  around { |example| travel_to(zone.local(2026, 10, 5, 12)) { example.run } }

  it "assumes the water matches the heater when nothing was reported" do
    expect(pool.estimated_water_temp).to eq(90)
    expect(build(:pool, assumed_setpoint: nil).estimated_water_temp).to be_nil
  end

  it "heats a reading during pump hours and loses heat the rest of the time" do
    pool.record_water_temp!(84, at: 1.day.ago)
    # Reaches 90 in the 4pm pump window, dips overnight, back to 90 at 4am, then
    # two hours of loss since the 10am pump stop.
    expect(pool.estimated_water_temp(air: air)).to be_between(89.5, 90)
  end

  it "loses heat faster with the cover off than on" do
    pool.update!(has_cover: true, cover_on: true, assumed_setpoint: 70)
    pool.record_water_temp!(90, at: 1.day.ago)
    covered = pool.estimated_water_temp(air: air)
    pool.update!(cover_on: false)
    expect(pool.estimated_water_temp(air: air)).to be < covered
  end

  it "banks the water temp reached so far when the setting or cover changes" do
    pool.record_water_temp!(84, at: 1.day.ago)
    pool.record_setpoint!(80, source: "user_reported", air: air)
    banked = pool.reload.water_temp.to_f
    expect(pool.water_temp_source).to eq("estimated")
    expect(banked).to be_between(89.5, 90)
    # Heater below the water now: it just loses heat to the air for a day.
    expect(pool.estimated_water_temp(1.day.from_now, air: air)).to be_between(banked - 4, banked - 2)
    pool.update!(has_cover: true)
    pool.record_cover!(false, air: air)
    expect(pool.reload.cover_on).to be false
  end

  it "uses the latest plan's air temperatures by default" do
    create(:recommendation, pool: pool, details: { "series" => [
      { "t" => 2.days.ago.iso8601, "air" => 40 }, { "t" => 1.day.from_now.iso8601, "air" => 40 }
    ] })
    pool.update!(assumed_setpoint: 70)
    pool.record_water_temp!(90, at: 1.day.ago)
    expect(pool.estimated_water_temp).to be < pool.estimated_water_temp(air: air)
  end

  it "lists check times over a period" do
    zone = ActiveSupport::TimeZone["America/Chicago"]
    times = pool.check_times_between(zone.local(2026, 10, 1, 8), zone.local(2026, 10, 2, 8))
    expect(times).to eq([ zone.local(2026, 10, 1, 17), zone.local(2026, 10, 2, 7) ])
  end
end

RSpec.describe Pool, "pump schedule" do
  it "defaults to 4-10am and 4-10pm" do
    expect(create(:user).pool.pump_schedule.describe).to eq("4am–10am and 4pm–10pm")
  end

  it "allows a single window" do
    pool = build(:pool, pump_on_1: "06:00", pump_off_1: "20:00", pump_on_2: "", pump_off_2: "")
    expect(pool).to be_valid
    expect(pool.pump_schedule.describe).to eq("6am–8pm")
  end

  it "rejects bad times and half a second window" do
    expect(build(:pool, pump_on_1: "25:00")).not_to be_valid
    expect(build(:pool, pump_on_2: "16:00", pump_off_2: "")).not_to be_valid
  end
end
