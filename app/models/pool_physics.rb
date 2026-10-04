# How the water responds to the heater setpoint. Below the setpoint the heater
# warms it at heat_rate; above it the heater is off and it cools at cool_rate,
# but never below the setpoint (the heater would kick back on). Rates in °F/day.
class PoolPhysics
  attr_reader :heat_per_hour, :cool_per_hour

  def initialize(heat_rate:, cool_rate:)
    @heat_per_hour = heat_rate.to_f / 24
    @cool_per_hour = cool_rate.to_f / 24
  end

  def self.for(pool) = new(heat_rate: pool.heat_rate_per_day, cool_rate: pool.cool_rate_per_day)

  # Water temp after +hours+ (may be fractional) at +setpoint+.
  def advance(temp, setpoint, hours)
    return temp if setpoint.nil? || hours <= 0

    if setpoint > temp
      [ temp + heat_per_hour * hours, setpoint ].min
    else
      [ temp - cool_per_hour * hours, setpoint ].max
    end
  end
end
