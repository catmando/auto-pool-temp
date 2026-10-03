module Recommenders
  # The simplest strategy: apply the target curve to the smoothed air
  # temperature right now. Ignores how long the pool takes to change.
  class Linear < Base
    def self.description = "Target for today's average air temperature. No look-ahead."

    def call
      air = smoothed.temp_at(now)
      raw = curve.pool_temp_for(air)
      Result.new(
        raw_target: raw,
        reason: "Average air temp around now is #{air.round}°F, so the pool should be #{raw.round}°F.",
        details: { strategy: "linear", series: series }
      )
    end
  end
end
