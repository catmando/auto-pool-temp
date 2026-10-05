# The ideal pool temperature for a given (24h-average) air temperature: a
# straight line through two anchor points (Advanced settings), shifted by the
# owner's comfort adjustment ("I like it warmer/cooler", -10..+10 °F), and
# never above MAX_POOL_TEMP. Extrapolates past the anchors.
class TargetCurve
  # Hotter than this isn't safe to soak in.
  MAX_POOL_TEMP = 104.0
  # The warmer/cooler setting (plus any party boost) stays within this many °F of neutral.
  MAX_ADJUSTMENT = 10

  attr_reader :hot_air, :hot_pool, :cold_air, :cold_pool, :adjustment

  def self.for(pool)
    new(hot_air: pool.hot_air_temp, hot_pool: pool.hot_pool_temp,
        cold_air: pool.cold_air_temp, cold_pool: pool.cold_pool_temp, adjustment: pool.comfort_adjustment)
  end

  def initialize(hot_air:, hot_pool:, cold_air:, cold_pool:, adjustment: 0)
    @hot_air, @hot_pool, @cold_air, @cold_pool = [ hot_air, hot_pool, cold_air, cold_pool ].map(&:to_f)
    @adjustment = adjustment.to_f
    raise ArgumentError, "hot and cold air temperatures must differ" if @hot_air == @cold_air
  end

  # °F of pool temperature per °F of air temperature (normally negative).
  def slope
    (hot_pool - cold_pool) / (hot_air - cold_air)
  end

  # The ideal with the comfort adjustment (or another one, e.g. a party boost).
  def pool_temp_for(air_temp, adjustment: self.adjustment)
    [ base_pool_temp_for(air_temp) + adjustment, MAX_POOL_TEMP ].min
  end

  # The line itself, before any adjustment or cap.
  def base_pool_temp_for(air_temp)
    cold_pool + slope * (air_temp - cold_air)
  end
end
