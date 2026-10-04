# Saved forecasts for test mode.
class ForecastSnapshotsController < ApplicationController
  # source=plan: the forecast behind the plan on the dashboard; otherwise the live forecast now.
  def create
    snapshot =
      if params[:source] == "plan" && (latest = current_pool.recommendations.recent.first)
        ForecastSnapshot.from_recommendation!(latest, name: params[:name])
      else
        ForecastSnapshot.capture!(current_pool, name: params[:name])
      end
    current_pool.update!(test_snapshot: snapshot) if params[:use] == "1"
    redirect_back fallback_location: edit_pool_path(anchor: "test-mode"), notice: "Saved test forecast “#{snapshot.name}”."
  rescue Weather::OpenMeteo::Error, ArgumentError => e
    redirect_back fallback_location: edit_pool_path(anchor: "test-mode"), alert: "Couldn't save the forecast: #{e.message}"
  end

  def destroy
    current_pool.forecast_snapshots.find(params[:id]).destroy
    redirect_to edit_pool_path(anchor: "test-mode"), notice: "Test forecast deleted."
  end
end
