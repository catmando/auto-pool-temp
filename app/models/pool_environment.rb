# How fast the water gains or loses heat to the air, in °F per day (negative =
# cooling), before the heater. The owner's standard model (2026-10-05):
#
#   Cover on:  100°F water at 35°F air loses ~3°F/day; loss shrinks in step with
#              the water-air gap. Once the air is warmer than the water it warms
#              at 0.3°F/day per degree of gap (10°F warmer air: +3°F/day).
#   Cover off: 100°F water loses ~6°F/day at 35°F air and ~2°F/day at 90°F air
#              (straight line). That's a bigger gap-driven loss plus a steady
#              evaporation loss, so it keeps cooling even on hot days.
#
# The pool's cooling factor scales all of it (1 = standard).
class PoolEnvironment
  REFERENCE_WATER = 100.0
  # Cover on: 3°F/day across a 65°F gap.
  COVERED_LOSS = 3.0 / (REFERENCE_WATER - 35)
  # Cover off: 6°F/day at a 65°F gap, 2°F/day at a 10°F gap.
  UNCOVERED_LOSS = (6.0 - 2.0) / ((REFERENCE_WATER - 35) - (REFERENCE_WATER - 90))
  EVAPORATION = 2.0 - UNCOVERED_LOSS * (REFERENCE_WATER - 90)
  # Air warmer than the water.
  GAIN = 0.3

  def initialize(factor: 1)
    @factor = factor.to_f
  end

  # °F per day for water at +water+ with air at +air+.
  def rate_per_day(water:, air:, cover_on:)
    gap = water - air
    rate =
      if gap >= 0
        -(cover_on ? COVERED_LOSS : UNCOVERED_LOSS) * gap
      else
        GAIN * -gap
      end
    rate -= EVAPORATION unless cover_on
    rate * @factor
  end

  def rate_per_hour(**options) = rate_per_day(**options) / 24.0
end
