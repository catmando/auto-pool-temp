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
    it { is_expected.to validate_numericality_of(:heat_rate_per_day).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:cool_rate_per_day).is_greater_than(0) }
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
      it "is due during a check hour in the pool's time zone" do
        expect(pool.due?(zone.local(2026, 10, 1, 7, 5))).to be true
        expect(pool.due?(zone.local(2026, 10, 1, 17, 59))).to be true
      end

      it "is not due outside check hours" do
        expect(pool.due?(zone.local(2026, 10, 1, 8, 5))).to be false
      end

      it "is not due twice in the same hour" do
        pool.update!(last_checked_at: zone.local(2026, 10, 1, 7, 1))
        expect(pool.due?(zone.local(2026, 10, 1, 7, 30))).to be false
        expect(pool.due?(zone.local(2026, 10, 1, 17, 5))).to be true
      end

      it "is never due without a location" do
        expect(build(:pool, :unlocated).due?(zone.local(2026, 10, 1, 7, 5))).to be false
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
    expect(build(:pool, strategy: "linear").recommender_class).to eq(Recommenders::Linear)
  end
end
