require "net/http"

module Weather
  # https://open-meteo.com — free, no API key, hourly forecasts up to 16 days.
  class OpenMeteo
    FORECAST_URL = "https://api.open-meteo.com/v1/forecast".freeze
    GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search".freeze

    Error = Class.new(StandardError)
    Place = Data.define(:name, :latitude, :longitude, :time_zone)

    def forecast(latitude:, longitude:, days: 10)
      json = get_json(FORECAST_URL,
        latitude: latitude, longitude: longitude,
        hourly: "temperature_2m", temperature_unit: "fahrenheit",
        timezone: "auto", timeformat: "unixtime", past_days: 1,
        forecast_days: days.clamp(1, 16))

      hourly = json.fetch("hourly") { raise Error, "no hourly data in response" }
      points = hourly.fetch("time").zip(hourly.fetch("temperature_2m")).filter_map do |epoch, temp|
        Forecast::Point.new(Time.zone.at(epoch), temp.to_f) unless temp.nil?
      end
      raise Error, "forecast contained no temperatures" if points.empty?

      Forecast.new(points, time_zone: json["timezone"], source: "open-meteo")
    end

    def search(query)
      json = get_json(GEOCODING_URL, name: query, count: 5, language: "en", format: "json")
      Array(json["results"]).map do |r|
        label = [ r["name"], r["admin1"], r["country_code"] ].compact.uniq.join(", ")
        Place.new(label, r["latitude"], r["longitude"], r["timezone"])
      end
    end

    private

    def get_json(url, params)
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      response = Net::HTTP.get_response(uri)
      raise Error, "Open-Meteo returned #{response.code}: #{response.body.to_s[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, SocketError, Timeout::Error, SystemCallError => e
      raise Error, "Open-Meteo request failed: #{e.message}"
    end
  end
end
