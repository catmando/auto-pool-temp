module Recommenders
  class Base
    SMOOTHING_HOURS = 24

    def self.label = name.demodulize.titleize
    def self.description = ""

    attr_reader :forecast, :curve, :heat_rate, :environment, :has_cover, :cover_on, :pump, :now, :next_check_at,
                :check_times, :water_temp, :warm_threshold, :parties, :current_setpoint,
                :pump_extended, :pump_boost_threshold

    # heat_rate: °F per hour the heater adds while the pump runs.
    # cooling_factor: scales the standard heat loss/gain to the air (PoolEnvironment).
    # has_cover / cover_on: whether the pool has a cover, and whether it's on now.
    # pump: when the heater can run (PumpSchedule).
    # check_times: when the setting can next be changed (scheduled checks), after now.
    # water_temp: best estimate of the actual water temperature now (nil if unknown).
    # warm_threshold: above this air temp a slightly cooler pool feels comfortable;
    #   below it, a slightly warmer one does.
    # parties: PoolParty::Window list; during one the ideal uses the party boost.
    # current_setpoint: what the heater is set to now, if known (planners prefer keeping it).
    # pump_extended: whether the pump is running around the clock now.
    # pump_boost_threshold: only suggest running the pump around the clock when, heating flat
    #   out on the normal schedule, the water would still fall this many °F short.
    def initialize(forecast:, curve:, heat_rate:, cooling_factor: 1, has_cover: false, cover_on: true,
                   pump: PumpSchedule.always_on, now: Time.current, next_check_at: nil,
                   check_times: nil, water_temp: nil, warm_threshold: 80, parties: [], current_setpoint: nil,
                   pump_extended: false, pump_boost_threshold: 3)
      @forecast = forecast
      @curve = curve
      @heat_rate = heat_rate.to_f
      @environment = PoolEnvironment.new(factor: cooling_factor)
      @has_cover = has_cover
      @cover_on = cover_on
      @pump = pump
      @now = now
      @check_times = check_times || default_check_times(next_check_at || now + 12.hours)
      @next_check_at = @check_times.first || now + 12.hours
      @water_temp = water_temp&.to_f
      @warm_threshold = warm_threshold.to_f
      @parties = parties
      @current_setpoint = current_setpoint&.to_i
      @pump_extended = pump_extended
      @pump_boost_threshold = pump_boost_threshold.to_f
    end

    # Settings that come from the pool (everything but the forecast, time, and water).
    def self.pool_options(pool)
      { curve: TargetCurve.for(pool), heat_rate: pool.heat_rate_per_hour, cooling_factor: pool.cooling_factor,
        has_cover: pool.has_cover, cover_on: pool.cover_on?, pump: pool.pump_schedule,
        warm_threshold: pool.warm_day_threshold, parties: pool.pool_parties.select(&:persisted?).map(&:window),
      current_setpoint: pool.assumed_setpoint, pump_extended: pool.pump_extended,
      pump_boost_threshold: pool.pump_boost_threshold }
    end

    def self.for_pool(pool, forecast:, now: Time.current, water_temp: pool.estimated_water_temp(now, air: forecast))
      new(forecast: forecast, now: now, check_times: pool.check_times_between(now, forecast.end_time),
          water_temp: water_temp, **pool_options(pool))
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

    def party_at(time) = parties.find { |p| p.cover?(time) }

    # The ideal at +time+: the curve with the comfort adjustment, plus the party boost during a
    # party (the total stays within TargetCurve::MAX_ADJUSTMENT of neutral).
    def desired_at(time)
      party = party_at(time)
      air = smoothed.temp_at(time)
      return curve.pool_temp_for(air) unless party

      curve.pool_temp_for(air, adjustment: [ curve.adjustment + party.boost, TargetCurve::MAX_ADJUSTMENT ].min)
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
