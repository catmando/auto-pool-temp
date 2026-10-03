# The straight line from outside air temperature to ideal pool temperature,
# defined by two user-chosen anchor points. Extrapolates past the anchors.
class TargetCurve
  attr_reader :hot_air, :hot_pool, :cold_air, :cold_pool

  def self.for(pool)
    new(hot_air: pool.hot_air_temp, hot_pool: pool.hot_pool_temp,
        cold_air: pool.cold_air_temp, cold_pool: pool.cold_pool_temp)
  end

  def initialize(hot_air:, hot_pool:, cold_air:, cold_pool:)
    @hot_air, @hot_pool, @cold_air, @cold_pool = [ hot_air, hot_pool, cold_air, cold_pool ].map(&:to_f)
    raise ArgumentError, "hot and cold air temperatures must differ" if @hot_air == @cold_air
  end

  # °F of pool temperature per °F of air temperature (normally negative).
  def slope
    (hot_pool - cold_pool) / (hot_air - cold_air)
  end

  def pool_temp_for(air_temp)
    cold_pool + slope * (air_temp - cold_air)
  end
end
