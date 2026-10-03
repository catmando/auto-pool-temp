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
end

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
end
