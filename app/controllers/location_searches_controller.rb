class LocationSearchesController < ApplicationController
  def create
    @query = params[:query].to_s.strip
    @places = @query.present? ? Weather.provider.search(@query) : []
  rescue Weather::OpenMeteo::Error => e
    @places = []
    @error = e.message
  ensure
    render layout: false unless performed?
  end
end
