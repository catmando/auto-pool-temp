# How comfortable a pool temperature is, given the ideal for the day and how
# warm the day feels. On a warm day (air at or above the warm-day threshold) a
# pool a little cooler than ideal still feels fine; on a cool day, a pool a
# little warmer than ideal does. "Fine" isn't "ideal", though: hitting the
# ideal is still best, so being off in the fine direction counts a little, and
# being off the other way is felt in full.
module Comfort
  # How far into the "fine" direction still feels fine, °F.
  LEEWAY = 2.0
  # How much a degree in the fine direction counts, compared to the other way.
  FINE_WEIGHT = 0.25

  module_function

  # °F of discomfort: 0 only when exactly on the ideal.
  def discomfort(pool:, ideal:, air:, warm_threshold:)
    off = pool - ideal
    fine_direction = air >= warm_threshold ? -1 : 1 # cooler is fine when warm, warmer when cool
    if off * fine_direction >= 0
      within = [ off.abs, LEEWAY ].min
      FINE_WEIGHT * within + (off.abs - within)
    else
      off.abs
    end
  end

  # Summary over hourly rows ({ pool:, desired:, smoothed_air: }).
  def score(rows, warm_threshold:)
    values = rows.map { |r| discomfort(pool: r[:pool], ideal: r[:desired], air: r[:smoothed_air], warm_threshold: warm_threshold) }
    errors = rows.map { |r| (r[:pool] - r[:desired]).abs }
    {
      # Plain average distance between expected water and ideal, °F.
      mean_error: (errors.sum / errors.size).round(2),
      # The same, with the comfortable direction counting less (what planners minimize).
      mean_discomfort: (values.sum / values.size).round(2),
      worst_discomfort: values.max.round(1),
      comfortable_share: (values.count { |v| v < 1 }.to_f / values.size).round(3)
    }
  end
end
