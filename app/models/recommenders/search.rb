module Recommenders
  # Tries schedules over the whole forecast and keeps the one with the least
  # discomfort (see Comfort), working backward from the end of the forecast one
  # check at a time (dynamic programming over water temperature). Each check
  # chooses a heater setting and, for pools with a cover, cover on or off.
  class Search < SchedulePlanner
    def self.label = "Search"
    def self.description = "Tries schedules across the whole forecast and picks the most comfortable."

    GRID_STEP = 0.5
    # Prefer keeping the current setting and cover unless a change is noticeably better (°F·hours).
    KEEP_SETTING_SLACK = 0.5

    private

    def choose_decisions
      values = backward_values
      temp = start_temp
      previous = Decision.new(start_temp.round, has_cover && cover_on)
      stages.map do |stage|
        decision = best_decision(stage, temp, values[stage.index + 1], previous)
        temp = run_stage(stage, temp, decision)
        previous = decision
      end
    end

    def actions
      @actions ||= cover_options.flat_map { |cover| setpoints.map { |sp| Decision.new(sp, cover) } }
    end

    def setpoints
      @setpoints ||= begin
        temps = desired + [ start_temp ]
        ((temps.min - 4).floor..(temps.max + 4).ceil).to_a
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
          actions.map { |decision| stage_cost(stage, temp, decision, following) }.min
        end
      end
      values
    end

    def best_decision(stage, temp, following, previous)
      costs = actions.to_h { |decision| [ decision, stage_cost(stage, temp, decision, following) ] }
      best = costs.values.min
      return previous if costs[previous] && costs[previous] <= best + KEEP_SETTING_SLACK

      near_best = costs.select { |_, c| c <= best + 1e-6 }.keys
      # Ties happen when the water can't reach any of them before the next check (every
      # setting above the water heats at the same rate). Prefer leaving the cover as it
      # is, then the setting nearest the coming day's ideal, so the instruction reads as
      # where the pool is headed.
      near_best.min_by { |d| [ d.cover_on == previous.cover_on ? 0 : 1, (d.setpoint - next_day_ideal(stage)).abs ] }
    end

    def next_day_ideal(stage)
      window = desired[stage.start, 24]
      window.sum / window.size
    end

    def stage_cost(stage, temp, decision, following)
      cost = 0.0
      (stage.start...stage.stop).each do |i|
        temp = step(temp, decision, i)
        cost += Comfort.discomfort(pool: temp, ideal: desired[i], air: day_air[i], warm_threshold: warm_threshold)
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
