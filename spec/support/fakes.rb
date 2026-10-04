# Stand-in weather provider. Defaults to a mild, flat forecast.
class FakeWeather
  attr_accessor :forecast_result, :places, :error
  attr_reader :requests

  def initialize(forecast: nil, places: [])
    @forecast_result = forecast
    @places = places
    @requests = []
  end

  def forecast(latitude:, longitude:, days:)
    @requests << { latitude: latitude, longitude: longitude, days: days }
    raise error if error

    @forecast_result || ForecastHelpers.flat_forecast(65)
  end

  def search(query)
    raise error if error

    @places
  end

  def time_zone_for(latitude:, longitude:)
    raise error if error

    "America/New_York"
  end
end

# Stand-in for both the SMS and Telegram senders.
class FakeSmsSender
  attr_reader :deliveries
  attr_accessor :fail_with

  def initialize
    @deliveries = []
  end

  def deliver(to:, body:)
    raise Sms::Error, fail_with if fail_with

    @deliveries << { to: to, body: body }
    Sms::Delivery.new(sid: "SM#{@deliveries.size}", status: "queued")
  end

  # Twilio-style status lookup; set +lookup_result+ to [status, error_code].
  attr_accessor :lookup_result

  def lookup(sid)
    status, code = lookup_result || [ "delivered", nil ]
    [ Sms::Delivery.new(sid: sid, status: status), code ]
  end

  def username = "pool_temp_bot"

  def last_body = @deliveries.last&.fetch(:body)
end

class FakeGeocoder
  attr_accessor :places, :error, :reverse_name

  def initialize
    @places = []
    @reverse_name = "14618, Town of Brighton, New York"
  end

  def search(_query)
    raise error if error

    @places
  end

  def reverse(latitude, longitude)
    raise error if error

    reverse_name && Geocoder::Place.new(reverse_name, latitude, longitude)
  end
end
