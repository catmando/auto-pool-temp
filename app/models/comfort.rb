# How comfortable a pool temperature is, given the ideal for the day and how
# warm the day feels. On a warm day (air at or above the warm-day threshold) a
# pool a little cooler than ideal still feels good; on a cool day, a pool a
# little warmer than ideal does. Being off in the other direction is felt
# right away.
module Comfort
  # How far into the "fine" direction still feels fine, °F.
  LEEWAY = 2.0

  module_function

  # °F of discomfort: 0 when it feels right.
  def discomfort(pool:, ideal:, air:, warm_threshold:)
    off = pool - ideal
    fine_direction = air >= warm_threshold ? -1 : 1 # cooler is fine when warm, warmer when cool
    if off * fine_direction >= 0
      [ off.abs - LEEWAY, 0 ].max
    else
      off.abs
    end
  end

  # Summary over hourly rows ({ pool:, desired:, smoothed_air: }).
  def score(rows, warm_threshold:)
    values = rows.map { |r| discomfort(pool: r[:pool], ideal: r[:desired], air: r[:smoothed_air], warm_threshold: warm_threshold) }
    {
      mean_discomfort: (values.sum / values.size).round(2),
      worst_discomfort: values.max.round(1),
      comfortable_share: (values.count { |v| v < 1 }.to_f / values.size).round(3)
    }
  end
end
