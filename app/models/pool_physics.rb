# How the water responds to the heater setting, hour by hour. Rates are °F
# per hour. The heater only runs while the pump runs:
#   pump on,  setting above the water: heats at heat_rate, up to the setting
#   pump on,  setting below the water: heater off, cools at cool_rate, but not
#                                      below the setting (the heater kicks in)
#   pump off: the heater can't run, so it cools at cool_rate, even below the setting
class PoolPhysics
  attr_reader :heat_rate, :cool_rate, :pump

  def initialize(heat_rate:, cool_rate:, pump: PumpSchedule.always_on)
    @heat_rate = heat_rate.to_f
    @cool_rate = cool_rate.to_f
    @pump = pump
  end

  def self.for(pool)
    new(heat_rate: pool.heat_rate_per_hour, cool_rate: pool.cool_rate_per_hour, pump: pool.pump_schedule)
  end

  # Water temp after one hour, with the pump running +pump_fraction+ of it.
  def step(temp, setpoint, pump_fraction = 1.0)
    return temp if setpoint.nil?

    on = pump_fraction
    temp =
      if setpoint > temp
        [ temp + heat_rate * on, setpoint ].min
      else
        [ temp - cool_rate * on, setpoint ].max
      end
    temp - cool_rate * (1 - on)
  end

  # Water temp at +to+, starting from +temp+ at +from+, under a fixed setting.
  def advance(temp, setpoint, from:, to:)
    return temp if setpoint.nil? || to <= from

    time = from
    while time + 1.hour <= to
      temp = step(temp, setpoint, pump.on_fraction(time))
      time += 1.hour
    end
    remainder = (to - time) / 3600.0
    return temp if remainder <= 0

    # Scale the last partial hour.
    temp + (step(temp, setpoint, pump.on_fraction(time)) - temp) * remainder
  end
end
