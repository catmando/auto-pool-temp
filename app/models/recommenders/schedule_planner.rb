module Recommenders
  # Shared machinery for planners that produce a heater *schedule*: one
  # setpoint per scheduled check, held until the next check. Subclasses
  # implement #choose_setpoints (one integer per stage). This class simulates
  # the water from its current temperature under that schedule, scores comfort,
  # and explains the first setting.
  class SchedulePlanner < Base
    Stage = Data.define(:index, :start, :stop, :at) # hour indexes [start, stop), start time

    def call
      setpoints = merge_ramps(choose_setpoints)
      rows = simulate(setpoints)
      Result.new(
        raw_target: setpoints.first.to_f,
        reason: explain(setpoints, rows),
        details: { strategy: strategy_key, series: rows.map { |r| r.merge(t: r[:t].iso8601) },
                   schedule: stages.zip(setpoints).map { |s, sp| { t: s.at.iso8601, setpoint: sp } },
                   water_now: start_temp.round(1), comfort: Comfort.score(rows, warm_threshold: warm_threshold) }
      )
    end

    def strategy_key = Recommenders.registry.key(self.class)

    private

    def choose_setpoints
      raise NotImplementedError
    end

    def physics = @physics ||= PoolPhysics.new(heat_rate: heat_rate, cool_rate: cool_rate, pump: pump)

    # Share of each hour the pump (and so the heater) runs.
    def pump_on = @pump_on ||= hours.map { |t| pump.on_fraction(t) }

    # Water temp after hour +i+ starting from +temp+.
    def step(temp, setpoint, i) = physics.step(temp, setpoint, pump_on[i])

    def run_stage(stage, temp, setpoint)
      (stage.start...stage.stop).each { |i| temp = step(temp, setpoint, i) }
      temp
    end

    def hours = sample_times

    def desired = @desired ||= hours.map { |t| desired_at(t) }

    def day_air = @day_air ||= hours.map { |t| smoothed.temp_at(t) }

    def warm?(index) = day_air[index] >= warm_threshold

    # Water temperature now: the estimate if we have one, otherwise assume it's at today's ideal.
    def start_temp = water_temp || desired.first

    # Stages run from now to the first check, then check to check.
    def stages
      @stages ||= begin
        starts = [ 0 ] + check_times.map { |t| ((t - hours.first) / 3600.0).ceil }.select { |i| i.positive? && i < hours.size }
        starts.uniq.each_with_index.map do |start, i|
          stop = starts[i + 1] || hours.size
          Stage.new(i, start, stop, hours[start])
        end
      end
    end

    # Pool temp at the end of each hour under +setpoints+ (one per stage).
    def simulate(setpoints)
      temp = start_temp
      stages.zip(setpoints).flat_map do |stage, setpoint|
        (stage.start...stage.stop).map do |i|
          temp = step(temp, setpoint, i)
          { t: hours[i], air: forecast.temp_at(hours[i]).round(1), smoothed_air: day_air[i].round(1),
            desired: desired[i].round(1), pool: temp.round(2), setpoint: setpoint, pump: pump_on[i].round(2) }
        end
      end
    end

    # While the water is still heating (or cooling) as fast as it can through a
    # stage, any setting further along does exactly the same thing. So when the
    # next stage keeps going the same way, use its setting now: the water is
    # unchanged, and a multi-day ramp becomes one change instead of one per check.
    def merge_ramps(setpoints)
      setpoints = setpoints.dup
      starts = water_at_stage_starts(setpoints)
      (setpoints.size - 2).downto(0) do |k|
        stage = stages[k]
        reached = run_stage(stage, starts[k], setpoints[k])
        heating_flat_out = (reached - run_stage(stage, starts[k], Float::INFINITY)).abs < 0.01
        cooling_flat_out = (reached - run_stage(stage, starts[k], -Float::INFINITY)).abs < 0.01
        setpoints[k] = setpoints[k + 1] if (heating_flat_out && setpoints[k + 1] > setpoints[k]) ||
                                            (cooling_flat_out && setpoints[k + 1] < setpoints[k])
      end
      setpoints
    end

    def water_at_stage_starts(setpoints)
      temp = start_temp
      [ temp ] + stages.zip(setpoints).map { |stage, setpoint| temp = run_stage(stage, temp, setpoint) }
    end

    def stage_ideal(stage) = desired[stage.start...stage.stop].sum / (stage.stop - stage.start)

    def explain(setpoints, _rows)
      setpoint = setpoints.first
      water = start_temp.round
      today = desired.first(24)
      ideal_today = (today.sum / today.size).round
      action =
        if setpoint > start_temp + 0.5 then "heat it up from about #{water}°F"
        elsif setpoint < start_temp - 0.5 then "let it cool off from about #{water}°F"
        else "hold it at about #{water}°F"
        end

      # Look up to 4 days ahead for the weather the setting is getting ready for.
      ahead = (24...[ 24 * 5, desired.size ].min).to_a
      if setpoint > ideal_today + 1 && ahead.any? && (peak = ahead.max_by { |i| desired[i] }) && desired[peak] > ideal_today + 1
        "Today's ideal is #{ideal_today}°F, but colder weather is coming (ideal #{desired[peak].round}°F around " \
          "#{fmt_time(hours[peak])}), so #{action} and stay a bit warm. A warmer pool is fine on a cool day."
      elsif setpoint < ideal_today - 1 && ahead.any? && (low = ahead.min_by { |i| desired[i] }) && desired[low] < ideal_today - 1
        "Today's ideal is #{ideal_today}°F, but warmer weather is coming (ideal #{desired[low].round}°F around " \
          "#{fmt_time(hours[low])}), so #{action} and stay a bit cool. A cooler pool is fine on a warm day."
      else
        "Today's average air temp is #{day_air.first.round}°F, so the ideal is about #{ideal_today}°F: #{action}."
      end
    end
  end
end
