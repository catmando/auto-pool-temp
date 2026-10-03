# "My heater is actually set to X" from the dashboard.
class SetpointsController < ApplicationController
  def update
    value = Integer(params[:assumed_setpoint], exception: false)
    if value && (40..110).cover?(value)
      current_pool.record_setpoint!(value, source: "user_reported")
      redirect_to root_path, notice: "Got it, the heater is set to #{value}°F."
    else
      redirect_to root_path, alert: "Enter a heater setting between 40 and 110°F."
    end
  end
end
