# The plan to show for a pool right now: the latest recommendation, re-made
# (without sending anything) when it's out of date. It's out of date when it's
# over an hour old, was made before the app booted (a deploy may have changed
# the planner), or anything it depends on changed since: settings, the heater
# setting, a water reading, test mode.
class CurrentPlan
  MAX_AGE = 1.hour

  attr_reader :recommendation, :error

  def self.for(pool) = new(pool).tap(&:load)

  def initialize(pool)
    @pool = pool
  end

  def load
    @recommendation = @pool.recommendations.recent.first
    refresh if stale?
    self
  end

  def stale?
    rec = @recommendation
    return true if rec.nil?
    return true if rec.details&.dig("test_snapshot_id") != @pool.test_snapshot_id
    return true if rec.created_at < Rails.application.config.booted_at
    return true if rec.created_at < @pool.updated_at

    !@pool.test_mode? && rec.created_at < MAX_AGE.ago
  end

  private

  def refresh
    @recommendation = PoolCheck.call(@pool, notify: false).recommendation
  rescue Weather::OpenMeteo::Error, ArgumentError => e
    @error = "Couldn't update the plan: #{e.message}"
  end
end
