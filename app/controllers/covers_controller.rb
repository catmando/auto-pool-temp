# "The cover is actually on/off" from the dashboard.
class CoversController < ApplicationController
  def update
    on = params[:on] == "1"
    current_pool.record_cover!(on)
    redirect_to root_path, notice: "Got it, the cover is #{on ? 'on' : 'off'}."
  end
end
