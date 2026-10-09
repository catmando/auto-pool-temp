module Recommenders
  # Tries schedules over the whole forecast and keeps the one with the least
  # discomfort (see Comfort), working backward from the end of the forecast one
  # check at a time (dynamic programming over water temperature). Each check
  # chooses a heater setting and, for pools with a cover, cover on or off.
  class Search < SchedulePlanner
    def self.label = "Search"
    def self.description = "Tries schedules across the whole forecast and picks the most comfortable."

    GRID_STEP = 0.5
    # Keep the current setting and cover unless a change is noticeably better (°F·hours of
    # discomfort saved). At 0.5 the plan flip-flopped (91, 92, 91, ...) about every check in
    # steady weather because of the pump-off dips; 2.0 keeps it steady (2026-10-05).
    KEEP_SETTING_SLACK = 2.0

    private

    def choose_decisions
      values = backward_values
      temp = start_temp
      previous = Decision.new(setpoint: current_setpoint || start_temp.round, cover_on: has_cover && cover_on,
                              pump_extra: pump_extended)
      stages.map do |stage|
        decision = best_decision(stage, temp, values[stage.index + 1], previous)
        temp = run_stage(stage, temp, decision)
        previous = decision
      end
    end

    def actions
      @actions ||= cover_options.flat_map { |cover| setpoints.map { |sp| Decision.new(setpoint: sp, cover_on: cover) } }
    end

    # Running the pump around the clock only makes sense for heating, with the cover on if there is one.
    def boost_actions
      @boost_actions ||= setpoints.map { |sp| Decision.new(setpoint: sp, cover_on: has_cover, pump_extra: true) }
    end

    # Running the pump around the clock is only on the table while it's needed (see
    # boost_needed?): the owner's rule is "only when more than the threshold short".
    # The cover only comes off to cool: with the setting at or above the water, the heater
    # would be fighting the open pool (owner, 2026-10-09).
    def actions_for(stage, temp)
      options = boost_needed?(stage, temp) ? actions + boost_actions : actions
      has_cover ? options.select { |d| d.cover_on || d.setpoint < temp } : options
    end

    def setpoints
      @setpoints ||= begin
        temps = desired + [ start_temp ]
        ((temps.min - 4).floor..[ (temps.max + 4).ceil, TargetCurve::MAX_POOL_TEMP.to_i ].min).to_a
      end
    end

    def grid
      @grid ||= begin
        # Room for the water to drift past the settings (warm air, pump-off cooling).
        low = setpoints.first - 6.0
        count = ((setpoints.last + 6.0 - low) / GRID_STEP).ceil
        Array.new(count + 1) { |i| low + i * GRID_STEP }
      end
    end

    # values[k][g]: least discomfort from stage k onward starting at grid[g].
    def backward_values
      values = Array.new(stages.size + 1)
      values[stages.size] = Array.new(grid.size, 0.0)
      stages.reverse_each do |stage|
        following = values[stage.index + 1]
        values[stage.index] = grid.map do |temp|
          actions_for(stage, temp).map { |decision| stage_cost(stage, temp, decision, following) }.min
        end
      end
      values
    end

    # Picks this check's decision. Every change is an alert, so changes have to
    # earn their keep:
    #   - the cover stays on unless taking it off is noticeably better (and goes
    #     back on once off stops being noticeably better)
    #   - the heater setting stays as it is unless a change is noticeably better
    def best_decision(stage, temp, following, previous)
      costs = actions_for(stage, temp).to_h { |decision| [ decision, stage_cost(stage, temp, decision, following) ] }
      best = costs.values.min

      # The pump stays on its normal schedule unless running it around the clock is
      # noticeably better (and goes back once it stops being noticeably better).
      normal = costs.reject { |d, _| d.pump_extra }
      costs = normal if normal.values.min <= best + KEEP_SETTING_SLACK
      best = costs.values.min

      covered = costs.select { |d, _| d.cover_on }
      if covered.any?
        costs = covered.values.min <= best + KEEP_SETTING_SLACK ? covered : costs.reject { |d, _| d.cover_on }
        best = costs.values.min
      end

      keep = previous.with(cover_on: costs.keys.first.cover_on, pump_extra: costs.keys.first.pump_extra)
      return keep if costs[keep] && costs[keep] <= best + KEEP_SETTING_SLACK

      # Ties happen when the water can't reach any of them before the next check (every
      # setting above the water heats at the same rate). Pick the setting nearest the
      # coming day's ideal, so the instruction reads as where the pool is headed.
      costs.select { |_, c| c <= best + 1e-6 }.keys.min_by { |d| (d.setpoint - next_day_ideal(stage)).abs }
    end

    def next_day_ideal(stage)
      window = desired[stage.start, 24]
      window.sum / window.size
    end

    def stage_cost(stage, temp, decision, following)
      cost = 0.0
      (stage.start...stage.stop).each do |i|
        temp = step(temp, decision, i)
        cost += Comfort.discomfort(pool: temp, ideal: desired[i], air: day_air[i], warm_threshold: warm_threshold,
                                   party: party[i])
      end
      cost + interpolate(following, temp)
    end

    def interpolate(values, temp)
      position = (temp - grid.first) / GRID_STEP
      return values.first if position <= 0
      return values.last if position >= values.size - 1

      lower = position.floor
      fraction = position - lower
      values[lower] * (1 - fraction) + values[lower + 1] * fraction
    end
  end
end
