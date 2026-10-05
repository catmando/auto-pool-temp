# A measured water temperature from the dashboard: logged with what the model
# expected (not used by the planner yet).
class WaterTempsController < ApplicationController
  def update
    value = Float(params[:water_temp], exception: false)
    if value && (32..110).cover?(value)
      log = PoolLog.water_reading!(current_pool, value, source: "web")
      expected = log.expected_water_temp ? " (expected about #{log.expected_water_temp.round}°F)" : ""
      redirect_to root_path, notice: "Logged the water at #{(value % 1).zero? ? value.to_i : value}°F#{expected}."
    else
      redirect_to root_path, alert: "Enter a water temperature between 32 and 110°F."
    end
  end
end
