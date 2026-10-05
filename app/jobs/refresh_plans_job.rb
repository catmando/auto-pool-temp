# Hourly (config/recurring.yml): bring every pool's plan up to date and tell any
# open dashboard to refresh itself (Turbo morphs the page in place).
class RefreshPlansJob < ApplicationJob
  queue_as :default

  def perform
    Pool.find_each do |pool|
      next unless pool.located? || pool.test_mode?

      CurrentPlan.for(pool)
      Turbo::StreamsChannel.broadcast_refresh_to(pool)
    end
  end
end
