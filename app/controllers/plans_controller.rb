# The current plan chart and table, as a Turbo Frame (Settings page).
class PlansController < ApplicationController
  def show
    @plan = CurrentPlan.for(current_pool) if current_pool.located? || current_pool.test_mode?
    render layout: false
  end
end
