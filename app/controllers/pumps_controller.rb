# "The pump is actually running around the clock / back on its schedule" from the dashboard.
class PumpsController < ApplicationController
  def update
    extended = params[:extended] == "1"
    current_pool.record_pump_extended!(extended)
    redirect_to root_path, notice: extended ? "Got it, the pump is running around the clock." : "Got it, the pump is back on its normal schedule."
  end
end
