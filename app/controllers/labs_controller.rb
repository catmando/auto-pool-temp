# Compare planning algorithms on the live forecast and made-up weather.
class LabsController < ApplicationController
  def show
    @lab = PlannerLab.new(current_pool)
  end
end
