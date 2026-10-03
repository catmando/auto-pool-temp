module Weather
  # An ordered series of air temperatures (°F) over time. Every provider is
  # normalized into this shape so the recommenders never care where the data
  # came from.
  class Forecast
    Point = Data.define(:time, :temp)

    attr_reader :points, :time_zone, :source

    def initialize(points, time_zone: nil, source: nil)
      @points = points.sort_by(&:time).freeze
      @time_zone = time_zone
      @source = source
      raise ArgumentError, "forecast has no data points" if @points.empty?
    end

    # Build an hourly forecast from daily highs/lows for providers that don't
    # give hourly data. Assumes the low happens around 3 AM and the high around
    # 3 PM local time, with a smooth (cosine) curve between them.
    #
    #   days: [{ date: Date, high: Float, low: Float }, ...]
    def self.from_daily(days, time_zone:, source: nil, low_hour: 3, high_hour: 15)
      zone = ActiveSupport::TimeZone[time_zone] || raise(ArgumentError, "unknown time zone #{time_zone}")
      knots = days.sort_by { |d| d[:date] }.flat_map do |day|
        midnight = zone.local(day[:date].year, day[:date].month, day[:date].day)
        [ Point.new(midnight + low_hour.hours, day[:low].to_f),
          Point.new(midnight + high_hour.hours, day[:high].to_f) ]
      end

      points = knots.each_cons(2).flat_map do |a, b|
        span = b.time - a.time
        (0...(span / 3600).round).map do |h|
          fraction = (h * 3600) / span
          eased = (1 - Math.cos(Math::PI * fraction)) / 2
          Point.new(a.time + h.hours, a.temp + (b.temp - a.temp) * eased)
        end
      end
      points << knots.last

      new(points, time_zone: time_zone, source: source)
    end

    def start_time = points.first.time
    def end_time = points.last.time

    # Linearly interpolated temperature at any time; clamps outside the range.
    def temp_at(time)
      return points.first.temp if time <= start_time
      return points.last.temp if time >= end_time

      after_index = points.bsearch_index { |p| p.time >= time }
      after = points[after_index]
      return after.temp if after.time == time

      before = points[after_index - 1]
      fraction = (time - before.time) / (after.time - before.time)
      before.temp + (after.temp - before.temp) * fraction
    end

    # Centered moving average. A pool is a big thermal mass, so it responds to
    # the day's overall warmth, not the afternoon peak. Near the ends of the
    # series the window shrinks to whatever data exists.
    def smoothed(window_hours: 24)
      half = window_hours.hours / 2
      averaged = points.map do |point|
        window = points.select { |p| (p.time - point.time).abs <= half }
        Point.new(point.time, window.sum(&:temp) / window.size)
      end
      self.class.new(averaged, time_zone: time_zone, source: source)
    end
  end
end
