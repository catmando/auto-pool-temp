require "net/http"

# Place lookup via OpenStreetMap's Nominatim: ZIP/postal codes and city names
# to coordinates, and coordinates to a readable name. Light use only (one user
# setting a location), per https://operations.osmfoundation.org/policies/nominatim/
class Geocoder
  URL = "https://nominatim.openstreetmap.org".freeze
  USER_AGENT = "AutoPoolTemp/1.0 (https://github.com/catmando/auto-pool-temp)".freeze

  Error = Class.new(StandardError)
  Place = Data.define(:name, :latitude, :longitude)

  mattr_accessor :default, default: nil
  def self.instance = default || new

  # A bare 5-digit number is treated as a US ZIP code.
  def search(query)
    query = query.to_s.strip
    return [] if query.empty?

    params = query.match?(/\A\d{5}\z/) ? { postalcode: query, country: "us" } : { q: query }
    Array(get("/search", params.merge(format: "jsonv2", limit: 5, addressdetails: 1))).map { |r| place(r) }
  end

  def reverse(latitude, longitude)
    result = get("/reverse", lat: latitude, lon: longitude, format: "jsonv2", zoom: 14, addressdetails: 1)
    result.is_a?(Hash) && result["error"].nil? ? place(result) : nil
  end

  private

  def place(result)
    address = result["address"] || {}
    town = address.values_at("suburb", "village", "town", "city", "hamlet").compact.first
    parts = [ address["postcode"], town, address["state"] ].compact.uniq
    name = parts.any? ? parts.join(", ") : result["display_name"].to_s.split(",").first(3).join(",")
    Place.new(name, result["lat"].to_f.round(5), result["lon"].to_f.round(5))
  end

  def get(path, params)
    uri = URI("#{URL}#{path}")
    uri.query = URI.encode_www_form(params)
    response = Net::HTTP.get_response(uri, "User-Agent" => USER_AGENT)
    raise Error, "location lookup failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError, SocketError, Timeout::Error, SystemCallError => e
    raise Error, "location lookup failed: #{e.message}"
  end
end
