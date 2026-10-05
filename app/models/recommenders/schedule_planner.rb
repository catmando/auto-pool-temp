module Recommenders
  # Shared machinery for planners that produce a *schedule*: at each scheduled
  # check, a heater setting and (for pools with a cover) whether the cover
  # should be on, held until the next check. Subclasses implement
  # #choose_decisions (one Decision per stage). This class simulates the water
  # from its current temperature under that schedule, scores comfort, and
  # explains the first decision.
  class SchedulePlanner < Base
    Stage = Data.define(:index, :start, :stop, :at) # hour indexes [start, stop), start time
    # pump_extra: run the pump (and so the heater) around the clock instead of on its schedule.
    Decision = Data.define(:setpoint, :cover_on, :pump_extra) do
      def initialize(setpoint:, cover_on:, pump_extra: false) = super
    end

    def call
      decisions = merge_ramps(choose_decisions)
      rows = simulate(decisions)
      first = decisions.first
      Result.new(
        raw_target: first.setpoint.to_f,
        reason: explain(decisions),
        details: { strategy: strategy_key, series: rows.map { |r| r.merge(t: r[:t].iso8601) },
                   schedule: stages.zip(decisions).map { |s, d| { t: s.at.iso8601, setpoint: d.setpoint, cover_on: d.cover_on, pump_extra: d.pump_extra } },
                   cover_on: has_cover ? first.cover_on : nil, pump_extra: first.pump_extra,
                   water_now: start_temp.round(1), comfort: Comfort.score(rows, warm_threshold: warm_threshold) }
      )
    end

    def strategy_key = Recommenders.registry.key(self.class)

    private

    def choose_decisions
      raise NotImplementedError
    end

    def physics = @physics ||= PoolPhysics.new(heat_rate: heat_rate, pump: pump, environment: environment)

    # Cover states the planner may choose. Pools without a cover are always uncovered.
    def cover_options = has_cover ? [ true, false ] : [ false ]

    # Share of each hour the pump (and so the heater) runs.
    def pump_on = @pump_on ||= hours.map { |t| pump.on_fraction(t) }

    def air = @air ||= hours.map { |t| forecast.temp_at(t) }

    # Water temp after hour +i+ starting from +temp+.
    def step(temp, decision, i)
      physics.step(temp, decision.setpoint, pump_fraction: decision.pump_extra ? 1.0 : pump_on[i], air: air[i],
                                            cover_on: decision.cover_on)
    end

    def run_stage(stage, temp, decision)
      (stage.start...stage.stop).each { |i| temp = step(temp, decision, i) }
      temp
    end

    def hours = sample_times

    def desired = @desired ||= hours.map { |t| desired_at(t) }

    def day_air = @day_air ||= hours.map { |t| smoothed.temp_at(t) }

    PARTY_LEAD = 24.hours
    PARTY_COOLDOWN = 48.hours

    # Per hour: :party during one, :around just before/after one, nil otherwise.
    def party
      @party ||= hours.map do |t|
        if party_at(t) then :party
        elsif parties.any? { |p| t >= p.starts_at - PARTY_LEAD && t < p.ends_at + PARTY_COOLDOWN } then :around
        end
      end
    end

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

    # Pool temp at the end of each hour under +decisions+ (one per stage).
    def simulate(decisions)
      temp = start_temp
      stages.zip(decisions).flat_map do |stage, decision|
        (stage.start...stage.stop).map do |i|
          temp = step(temp, decision, i)
          { t: hours[i], air: air[i].round(1), smoothed_air: day_air[i].round(1), desired: desired[i].round(1),
            pool: temp.round(2), setpoint: decision.setpoint, cover_on: decision.cover_on, pump: (decision.pump_extra ? 1.0 : pump_on[i]).round(2),
            pump_extra: decision.pump_extra, party: party[i] }
        end
      end
    end

    # While the water is still heating as fast as it can through a stage, any
    # higher setting does exactly the same thing (and while it's cooling, any
    # lower one). So when the next stage keeps going the same way, use its
    # setting now: the water is unchanged, and a long ramp becomes one change
    # instead of one per check.
    def merge_ramps(decisions)
      decisions = decisions.dup
      starts = water_at_stage_starts(decisions)
      (decisions.size - 2).downto(0) do |k|
        current, following = decisions[k], decisions[k + 1]
        next unless current.cover_on == following.cover_on && current.pump_extra == following.pump_extra

        stage = stages[k]
        reached = run_stage(stage, starts[k], current)
        heating_flat_out = (reached - run_stage(stage, starts[k], current.with(setpoint: Float::INFINITY))).abs < 0.01
        cooling_flat_out = (reached - run_stage(stage, starts[k], current.with(setpoint: -Float::INFINITY))).abs < 0.01
        if (heating_flat_out && following.setpoint > current.setpoint) || (cooling_flat_out && following.setpoint < current.setpoint)
          decisions[k] = following
        end
      end
      decisions
    end

    def water_at_stage_starts(decisions)
      temp = start_temp
      [ temp ] + stages.zip(decisions).map { |stage, decision| temp = run_stage(stage, temp, decision) }
    end

    BOOST_LOOKAHEAD = 24 # hours past the stage to look for a shortfall

    # May the pump run around the clock in this stage? Only when the normal pump hours
    # can't keep up with the weather: starting on the ideal and heating flat out on the
    # normal schedule, the water would still fall more than pump_boost_threshold short
    # during the stage or the day after. This deliberately ignores the water's actual
    # temperature, so being cooler never "unlocks" the option (the planner would learn
    # to run cool). The water already being far below the ideal right now counts too.
    def boost_needed?(stage, temp = nil)
      return true if temp && stage.index.zero? && desired[stage.start] - temp > pump_boost_threshold

      @boost_needed ||= {}
      @boost_needed.fetch(stage.index) do
        flat_out = Decision.new(setpoint: TargetCurve::MAX_POOL_TEMP, cover_on: has_cover)
        water = desired[stage.start]
        last = [ stage.stop + BOOST_LOOKAHEAD, hours.size ].min
        @boost_needed[stage.index] = (stage.start...last).any? do |i|
          water = step(water, flat_out, i)
          desired[i] - water > pump_boost_threshold
        end
      end
    end

    def stage_ideal(stage) = desired[stage.start...stage.stop].sum / (stage.stop - stage.start)

    def explain(decisions)
      setpoint = decisions.first.setpoint
      water = start_temp.round
      today = desired.first(24)
      ideal_today = (today.sum / today.size).round
      action =
        if setpoint > start_temp + 0.5 then "heat it up from about #{water}°F"
        elsif setpoint < start_temp - 0.5 then "let it cool off from about #{water}°F"
        else "hold it at about #{water}°F"
        end
      action += cover_advice(decisions.first)
      action += ", and run the pump around the clock until it catches up" if decisions.first.pump_extra

      if (next_party = party.index(:party)) && next_party < 48 && setpoint > ideal_today + 1
        return "Getting ready for your pool party at #{fmt_time(hours[next_party])} " \
               "(target #{desired[next_party].round}°F), so #{action}."
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

    def cover_advice(decision)
      return "" unless has_cover

      decision.cover_on ? " (keep the cover on)" : " with the cover off so it cools faster"
    end
  end
end
