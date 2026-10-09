require "rails_helper"

# The cover only comes off to cool the pool. Taking it off while the heater is
# heating (or holding) wastes the heat; on 2026-10-09 a party plan said "set the heater
# to 102°F" and "remove the cover for rapid cooling" in the same alert.
RSpec.describe Recommenders::Search, "cover rule" do
  # The owner's pool: default curve, comfort +7, pump 4–10am and 4–10pm (Eastern = UTC-4).
  let(:curve) { TargetCurve.new(hot_air: 95, hot_pool: 75, cold_air: 35, cold_pool: 98, adjustment: 7) }
  let(:pump) { PumpSchedule.new([ %w[08:00 14:00], %w[20:00 02:00] ]) }

  def plan(now:, water:, air:, parties: [], setpoint: nil, cover_on: true)
    forecast = hourly_forecast(start: now.beginning_of_hour, days: 8) { |h| air.call(h) }
    checks = (0..8).flat_map { |d| [ 11, 21 ].map { |h| now.beginning_of_day + d.days + h.hours } }.select { |t| t > now }
    described_class.new(forecast: forecast, curve: curve, heat_rate: 2, has_cover: true, cover_on: cover_on, pump: pump,
                        now: now, check_times: checks.select { |t| t <= forecast.end_time }, water_temp: water,
                        parties: parties, current_setpoint: setpoint).call
  end

  # [setpoint, cover_on, water when that setting starts] for every check in the plan.
  def stages(result)
    series = result.details[:series]
    result.details[:schedule].map do |s|
      before = series.select { |r| r[:t] < s[:t] }.last
      [ s[:setpoint], s[:cover_on], before ? before[:pool] : result.details[:water_now] ]
    end
  end

  def heating_with_cover_off(result) = stages(result).select { |sp, cover, water| !cover && sp >= water - 0.01 }

  it "keeps the cover on through a party on a cool day (the situation of the 2026-10-09 alert)" do
    now = Time.utc(2026, 10, 9, 11, 5)
    party = PoolParty::Window.new(Time.utc(2026, 10, 9, 8), Time.utc(2026, 10, 10, 3, 59), 3)
    result = plan(now: now, water: 101, air: ->(_) { 52 }, parties: [ party ], setpoint: 102, cover_on: false)
    expect(result.details[:cover_on]).to be true
    expect(heating_with_cover_off(result)).to be_empty
    expect(result.reason).not_to include("cover off")
    expect(result.reason).to start_with("Your pool party is on (target") # not "getting ready for" a party already under way
  end

  it "never takes the cover off while heating or holding, whatever the hour, water, or party" do
    weathers = { steady: ->(_) { 52 }, warming: ->(h) { h < 48 ? 50 : 70 }, cooling: ->(h) { h < 48 ? 70 : 45 } }
    (0...24).step(3).each do |hour|
      now = Time.utc(2026, 10, 9) + hour.hours
      party = PoolParty::Window.new(now + 30.hours, now + 40.hours, 3)
      weathers.each do |name, air|
        [ 95, 99, 103 ].each do |water|
          [ [], [ party ] ].each do |parties|
            offenders = heating_with_cover_off(plan(now: now, water: water, air: air, parties: parties))
            expect(offenders).to be_empty, "#{name}, start #{hour}:00 UTC, water #{water}, party #{parties.any?}: #{offenders}"
          end
        end
      end
    end
  end

  it "still takes the cover off to cool a pool that's too warm" do
    result = plan(now: Time.utc(2026, 10, 9, 11), water: 103, air: ->(_) { 75 })
    expect(stages(result).first(2).map { |_, cover, _| cover }).to include(false)
  end
end
