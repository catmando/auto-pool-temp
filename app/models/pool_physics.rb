# How the water temperature changes hour by hour.
#   - It always gains or loses heat to the air (PoolEnvironment), depending on
#     the air temperature and whether the cover is on.
#   - The heater only runs while the pump runs. Then, if the water is below the
#     setting, it adds up to heat_rate °F/hour, stopping at the setting.
class PoolPhysics
  attr_reader :heat_rate, :pump, :environment

  def initialize(heat_rate:, pump: PumpSchedule.always_on, environment: PoolEnvironment.new)
    @heat_rate = heat_rate.to_f
    @pump = pump
    @environment = environment
  end

  def self.for(pool)
    new(heat_rate: pool.heat_rate_per_hour, pump: pool.pump_schedule,
        environment: PoolEnvironment.new(factor: pool.cooling_factor))
  end

  # Water temp after one hour with the pump running +pump_fraction+ of it.
  # A nil setting means the heater never runs.
  def step(temp, setpoint, pump_fraction: 1.0, air:, cover_on: true)
    temp += environment.rate_per_hour(water: temp, air: air, cover_on: cover_on)
    if setpoint && pump_fraction.positive? && temp < setpoint
      temp = [ temp + heat_rate * pump_fraction, setpoint ].min
    end
    temp
  end

  # Water temp at +to+, starting from +temp+ at +from+, under a fixed setting.
  # +air+ is anything with temp_at(time) (a Weather::Forecast).
  def advance(temp, setpoint, from:, to:, air:, cover_on: true)
    return temp if to <= from

    time = from
    while time + 1.hour <= to
      temp = step(temp, setpoint, pump_fraction: pump.on_fraction(time), air: air.temp_at(time), cover_on: cover_on)
      time += 1.hour
    end
    remainder = (to - time) / 3600.0
    return temp if remainder <= 0

    # Scale the last partial hour.
    after = step(temp, setpoint, pump_fraction: pump.on_fraction(time), air: air.temp_at(time), cover_on: cover_on)
    temp + (after - temp) * remainder
  end
end
