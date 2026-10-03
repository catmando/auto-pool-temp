module ForecastHelpers
  module_function

  # Hourly forecast starting a day before +start+ (like Open-Meteo's past_days=1),
  # with temps from a block taking hours-since-start.
  def hourly_forecast(start: Time.current.beginning_of_hour, days: 10, time_zone: "UTC", &temp_for)
    points = (-24..(days * 24)).map do |h|
      Weather::Forecast::Point.new(start + h.hours, temp_for.call(h).to_f)
    end
    Weather::Forecast.new(points, time_zone: time_zone, source: "test")
  end

  def flat_forecast(temp, **options)
    hourly_forecast(**options) { temp }
  end

  # Air temp that steps from +before+ to +after+ at +at_hour+.
  def step_forecast(before:, after:, at_hour:, **options)
    hourly_forecast(**options) { |h| h < at_hour ? before : after }
  end
end
