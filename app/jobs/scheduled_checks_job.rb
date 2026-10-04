# Runs hourly (config/recurring.yml) and enqueues a check for every pool whose
# local check hour has arrived.
class ScheduledChecksJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current)
    Pool.where(test_snapshot_id: nil).find_each do |pool|
      PoolCheckJob.perform_later(pool) if pool.due?(now)
    end
  end
end
