class PoolCheckJob < ApplicationJob
  queue_as :default
  retry_on Weather::OpenMeteo::Error, wait: 10.minutes, attempts: 3

  def perform(pool)
    PoolCheck.call(pool)
  end
end
