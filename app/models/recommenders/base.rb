module Recommenders
  class Base
    SMOOTHING_HOURS = 24

    def self.label = name.demodulize.titleize
    def self.description = ""

    attr_reader :forecast, :curve, :heat_rate, :cool_rate, :now, :next_check_at, :check_times,
                :water_temp, :warm_threshold

    # heat_rate / cool_rate are °F per day.
    # check_times: when the heater setting can next be changed (scheduled checks), after now.
    # water_temp: best estimate of the actual water temperature now (nil if unknown).
    # warm_threshold: above this air temp a slightly cooler pool feels comfortable;
    #   below it, a slightly warmer one does.
    def initialize(forecast:, curve:, heat_rate:, cool_rate:, now: Time.current, next_check_at: nil,
                   check_times: nil, water_temp: nil, warm_threshold: 80)
      @forecast = forecast
      @curve = curve
      @heat_rate = heat_rate.to_f
      @cool_rate = cool_rate.to_f
      @now = now
      @check_times = check_times || default_check_times(next_check_at || now + 12.hours)
      @next_check_at = @check_times.first || now + 12.hours
      @water_temp = water_temp&.to_f
      @warm_threshold = warm_threshold.to_f
    end

    def self.for_pool(pool, forecast:, now: Time.current)
      new(forecast: forecast, curve: TargetCurve.for(pool),
          heat_rate: pool.heat_rate_per_day, cool_rate: pool.cool_rate_per_day, now: now,
          check_times: pool.check_times_between(now, forecast.end_time),
          water_temp: pool.estimated_water_temp(now), warm_threshold: pool.warm_day_threshold)
    end

    def call
      raise NotImplementedError
    end

    private

    def default_check_times(first)
      times = []
      t = first
      while t <= forecast.end_time
        times << t
        t += 12.hours
      end
      times
    end

    def smoothed
      @smoothed ||= forecast.smoothed(window_hours: SMOOTHING_HOURS)
    end

    # Hourly sample times, on the hour, from the current hour to the end of the forecast.
    def sample_times
      @sample_times ||= begin
        times = []
        t = now.beginning_of_hour
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
