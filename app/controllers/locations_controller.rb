# Saves the location confirmed on the settings map. Fills in a readable name
# (if the user picked a spot on the map) and the local time zone.
class LocationsController < ApplicationController
  def update
    latitude = Float(params[:latitude], exception: false)
    longitude = Float(params[:longitude], exception: false)
    unless latitude && longitude && latitude.between?(-90, 90) && longitude.between?(-180, 180)
      return redirect_to(edit_pool_path, alert: "Pick a spot on the map or search for your ZIP code first.")
    end

    name = params[:name].presence || lookup_name(latitude, longitude)
    attrs = { latitude: latitude.round(5), longitude: longitude.round(5), location_name: name }
    zone = lookup_time_zone(latitude, longitude)
    attrs[:time_zone] = zone if zone && ActiveSupport::TimeZone[zone]
    current_pool.update!(attrs)
    redirect_to edit_pool_path, notice: "Location set to #{name}."
  end

  private

  def lookup_name(latitude, longitude)
    Geocoder.instance.reverse(latitude, longitude)&.name || "#{latitude.round(3)}, #{longitude.round(3)}"
  rescue Geocoder::Error
    "#{latitude.round(3)}, #{longitude.round(3)}"
  end

  def lookup_time_zone(latitude, longitude)
    Weather.provider.time_zone_for(latitude: latitude, longitude: longitude)
  rescue Weather::OpenMeteo::Error
    nil
  end
end
