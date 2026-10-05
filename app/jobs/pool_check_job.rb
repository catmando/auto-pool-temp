class PoolCheckJob < ApplicationJob
  queue_as :default
  retry_on Weather::OpenMeteo::Error, wait: 10.minutes, attempts: 3

  # A scheduled check (may send an alert), then refresh any open dashboard.
  def perform(pool)
    PoolCheck.call(pool)
    Turbo::StreamsChannel.broadcast_refresh_to(pool)
  end
end
