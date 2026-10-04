# Turn test mode on (plan against a saved forecast) or off.
class TestModesController < ApplicationController
  def update
    snapshot = params[:snapshot_id].presence && current_pool.forecast_snapshots.find(params[:snapshot_id])
    current_pool.update!(test_snapshot: snapshot)
    notice = snapshot ? "Test mode on: planning with “#{snapshot.name}”. No alerts are sent." : "Test mode off: back to the live forecast."
    redirect_back fallback_location: root_path, notice: notice
  end
end
