# ZIP code / city lookup for the settings map (JSON).
class LocationSearchesController < ApplicationController
  def create
    places = Geocoder.instance.search(params[:query])
    render json: places.map(&:to_h)
  rescue Geocoder::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end
end
