module Recommenders
  class Base
    SMOOTHING_HOURS = 24

    def self.label = name.demodulize.titleize
    def self.description = ""

    attr_reader :forecast, :curve, :heat_rate, :cool_rate, :now, :next_check_at

    # heat_rate / cool_rate are °F per day.
    def initialize(forecast:, curve:, heat_rate:, cool_rate:, now: Time.current, next_check_at: nil)
      @forecast = forecast
      @curve = curve
      @heat_rate = heat_rate.to_f
      @cool_rate = cool_rate.to_f
      @now = now
      @next_check_at = next_check_at || now + 12.hours
    end

    def self.for_pool(pool, forecast:, now: Time.current)
      new(forecast: forecast, curve: TargetCurve.for(pool),
          heat_rate: pool.heat_rate_per_day, cool_rate: pool.cool_rate_per_day,
          now: now, next_check_at: pool.next_check_after(now))
    end

    def call
      raise NotImplementedError
    end

    private

    def smoothed
      @smoothed ||= forecast.smoothed(window_hours: SMOOTHING_HOURS)
    end

    # Hourly sample times from now until the end of the forecast.
    def sample_times
      @sample_times ||= begin
        times = []
        t = now
        while t <= forecast.end_time
          times << t
          t += 1.hour
        end
        times.presence || [ now ]
      end
    end

    def desired_at(time)
      curve.pool_temp_for(smoothed.temp_at(time))
    end

    def series(plan: nil)
      sample_times.each_with_index.map do |t, i|
        row = { t: t.iso8601, air: forecast.temp_at(t).round(1), smoothed_air: smoothed.temp_at(t).round(1),
                desired: desired_at(t).round(1) }
        row[:plan] = plan[i].round(1) if plan
        row
      end
    end

    def fmt_time(time)
      zone = forecast.time_zone.presence || Time.zone.name
      time.in_time_zone(zone).strftime("%a %-l%P")
    end
  end
end
