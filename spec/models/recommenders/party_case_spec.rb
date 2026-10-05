require "rails_helper"

# The owner's approved party case (2026-10-05): the Rochester forecast as of 5pm
# Oct 5, with a party Wednesday Oct 7 from noon to midnight, +10°F above neutral
# in total. The approved graph (plan #31 in production) was made with the
# everyday comfort setting at +5 and the party taking it to +10. The owner liked
# it: the heater is kept high through Tuesday night and topped up in the morning
# pump window, so the water is on target at noon and stays there into the evening.
RSpec.describe Recommenders::Search, "the owner's Rochester pool party" do
  let(:data) { JSON.parse(Rails.root.join("spec/fixtures/party/rochester_2026_10_05_party.json").read) }
  let(:zone) { ActiveSupport::TimeZone[data["time_zone"]] }
  let(:now) { Time.zone.parse(data["taken_at"]) }
  let(:forecast) do
    Weather::Forecast.new(data["points"].map { |t, air| Weather::Forecast::Point.new(Time.zone.at(t), air.to_f) },
                          time_zone: data["time_zone"])
  end
  let(:party_start) { Time.zone.parse(data["party"]["starts_at"]) }
  let(:party_end) { Time.zone.parse(data["party"]["ends_at"]) }

  def plan(comfort:, boost:)
    pool = Pool.new(hot_air_temp: 95, hot_pool_temp: 75, cold_air_temp: 35, cold_pool_temp: 98, comfort_adjustment: comfort,
                    heat_rate_per_hour: 2, cooling_factor: 1, has_cover: false, warm_day_threshold: 80, checks_per_day: 2,
                    pump_on_1: "04:00", pump_off_1: "10:00", pump_on_2: "16:00", pump_off_2: "22:00", time_zone: data["time_zone"])
    party = PoolParty::Window.new(party_start, party_end, boost)
    described_class.new(forecast: forecast, now: now, water_temp: data["water_temp"],
                        check_times: pool.check_times_between(now, forecast.end_time),
                        **Recommenders::Base.pool_options(pool).merge(parties: [ party ])).call.details[:series]
  end

  def at(rows, time) = rows.find { |r| Time.zone.parse(r[:t]) == time }

  describe "as approved: everyday +5, party +5 (+10 in total)" do
    let(:rows) { plan(comfort: 5, boost: 5) }

    it "reproduces the approved plan around the party, hour by hour" do
      data["approved"].each do |t, water, setpoint|
        row = at(rows, Time.zone.at(t))
        expect([ row[:pool], row[:setpoint] ]).to match([ be_within(0.05).of(water), setpoint ]), "at #{row[:t]}"
      end
    end

    it "has the water on target when the party starts, and keeps it there" do
      start = rows.index { |r| Time.zone.parse(r[:t]) == party_start }
      expect(rows[start][:pool]).to be >= rows[start][:desired] - 0.3
      rows[start, 6].each { |r| expect(r[:pool]).to be >= r[:desired] - 0.5, "at #{r[:t]}" }
    end

    it "keeps the pool warm the night before instead of letting it cool" do
      night = (party_start - 14.hours...party_start - 8.hours) # Tuesday 10pm to Wednesday 4am, pump off
      rows.select { |r| night.cover?(Time.zone.parse(r[:t])) }.each { |r| expect(r[:pool]).to be >= 98.5, "at #{r[:t]}" }
    end
  end

  describe "with everyday comfort at 0 and a +10 party" do
    let(:rows) { plan(comfort: 0, boost: 10) }

    it "aims for the same party target" do
      start = at(rows, party_start)
      usual = TargetCurve.new(hot_air: 95, hot_pool: 75, cold_air: 35, cold_pool: 98).pool_temp_for(start[:smoothed_air])
      expect(start[:desired]).to be_within(0.1).of(usual + 10)
    end

    it "heats up in the morning pump window and is on target when the party starts" do
      start = rows.index { |r| Time.zone.parse(r[:t]) == party_start }
      expect(rows[start][:pool]).to be >= rows[start][:desired] - 0.3
      rows[start, 6].each { |r| expect(r[:pool]).to be >= r[:desired] - 0.5, "at #{r[:t]}" }
    end
  end
end
