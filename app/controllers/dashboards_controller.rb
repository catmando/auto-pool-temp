class DashboardsController < ApplicationController
  # How old a plan can get before the dashboard makes a fresh one.
  PLAN_MAX_AGE = 1.hour

  def show
    pool = current_pool
    return redirect_to(edit_pool_path, notice: "Set your pool's location first.") unless pool.located? || pool.test_mode?

    @recommendation = pool.recommendations.recent.first
    refresh_plan if stale?(@recommendation)
    @text_messages = pool.text_messages.recent.limit(5)
  end

  private

  # Re-plan (without sending anything) whenever the plan is old, or anything it
  # depends on changed since: settings, the heater setting, a water reading, test mode.
  def stale?(recommendation)
    return true if recommendation.nil?
    return true if recommendation.details&.dig("test_snapshot_id") != current_pool.test_snapshot_id
    return true if recommendation.created_at < Rails.application.config.booted_at # made by older code
    return false if current_pool.test_mode? && recommendation.created_at >= current_pool.updated_at

    recommendation.created_at < PLAN_MAX_AGE.ago || recommendation.created_at < current_pool.updated_at
  end

  def refresh_plan
    @recommendation = PoolCheck.call(current_pool, notify: false).recommendation
  rescue Weather::OpenMeteo::Error, ArgumentError => e
    flash.now[:alert] = "Couldn't update the plan: #{e.message}"
  end
end
