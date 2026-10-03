class DashboardsController < ApplicationController
  def show
    return redirect_to(edit_pool_path, notice: "Set your pool's location first.") unless current_pool.located?

    @recommendation = current_pool.recommendations.recent.first
    @text_messages = current_pool.text_messages.recent.limit(5)
  end
end
