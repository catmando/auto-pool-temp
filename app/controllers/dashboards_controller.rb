class DashboardsController < ApplicationController
  def show
    pool = current_pool
    return redirect_to(edit_pool_path, notice: "Set your pool's location first.") unless pool.located? || pool.test_mode?

    plan = CurrentPlan.for(pool)
    @recommendation = plan.recommendation
    flash.now[:alert] = plan.error if plan.error
    @text_messages = pool.text_messages.recent.limit(5)
  end
end
