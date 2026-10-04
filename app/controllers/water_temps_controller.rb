# "The water is actually X°F" from the dashboard.
class WaterTempsController < ApplicationController
  def update
    value = Float(params[:water_temp], exception: false)
    if value && (32..110).cover?(value)
      current_pool.record_water_temp!(value)
      redirect_to root_path, notice: "Got it, the water is #{(value % 1).zero? ? value.to_i : value}°F. Run a check to re-plan from there."
    else
      redirect_to root_path, alert: "Enter a water temperature between 32 and 110°F."
    end
  end
end
