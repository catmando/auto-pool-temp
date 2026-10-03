module Recommenders
  # Plans ahead using the pool's heat-up / cool-down rates.
  #
  # 1. desired(t): the target curve applied to the 24h-smoothed forecast.
  #
  # 2. Backward pass (anticipation). Walk from the horizon back to now:
  #      plan[k] = desired[k] clamped to [plan[k+1] - heat_per_hour,
  #                                       plan[k+1] + cool_per_hour]
  #    so the pool starts changing early enough to hit a later target. The
  #    clamp is only applied when the later target is at least as "extreme"
  #    (far from the curve's midpoint) as desired[k]. Pre-heat for a cold snap
  #    or pre-cool for a heat wave, yes; but never cool the pool *during* a
  #    cold snap just because mild weather follows it. Being off-target in
  #    mild weather matters less than being off-target in extreme weather.
  #
  # 3. Forward pass (physics). Where anticipation was skipped, the pool can't
  #    jump, so it lags behind desired at its natural rate. This only affects
  #    the plan line shown in the chart.
  #
  # 4. Decision: if an anticipation clamp is active anywhere between now and
  #    the next scheduled check, recommend the target being chased (a heater
  #    runs flat-out until it reaches its setpoint, so set it to the goal, not
  #    an intermediate value). Otherwise recommend desired(now).
  class Lookahead < Base
    def self.description = "Starts heating or cooling early so the pool is on target when the weather changes."

    def call
      desired = sample_times.map { |t| desired_at(t) }
      anticipated, mode, goal, goal_index = backward_pass(desired)
      plan = forward_pass(anticipated)

      hours_to_next_check = ((next_check_at - now) / 3600.0).ceil.clamp(1, sample_times.size)
      urgent = (0...hours_to_next_check).find { |k| mode[k] }

      if urgent
        raw = goal[urgent]
        when_needed = fmt_time(sample_times[goal_index[urgent]])
        action = mode[urgent] == :heat ? "heating" : "cooling"
        reason = "Forecast needs the pool at #{raw.round}°F by #{when_needed}; " \
                 "at #{rate_for(mode[urgent])}°F/day it has to start #{action} now."
      else
        raw = desired.first
        reason = "Average air temp around now is #{smoothed.temp_at(now).round}°F, so the pool should be #{raw.round}°F."
      end

      Result.new(raw_target: raw, reason: reason,
                 details: { strategy: "lookahead", series: series(plan: plan),
                            urgent_mode: urgent && mode[urgent].to_s })
    end

    private

    def heat_step = heat_rate / 24.0
    def cool_step = cool_rate / 24.0

    # The pool temp for "mild" weather: halfway between the curve's anchors.
    def midpoint = @midpoint ||= (curve.hot_pool + curve.cold_pool) / 2.0

    def extremeness(temp) = (temp - midpoint).abs

    def rate_for(mode)
      (mode == :heat ? heat_rate : cool_rate).to_s.sub(/\.0\z/, "")
    end

    def backward_pass(desired)
      n = desired.size
      plan = Array.new(n)
      mode = Array.new(n) # nil, :heat or :cool
      goal = Array.new(n)
      goal_index = Array.new(n)

      plan[n - 1] = desired[n - 1]
      goal[n - 1] = desired[n - 1]
      goal_index[n - 1] = n - 1

      (n - 2).downto(0) do |k|
        chasing = plan[k + 1]
        worth_anticipating = extremeness(goal[k + 1]) >= extremeness(desired[k])

        if worth_anticipating && desired[k] < chasing - heat_step
          plan[k] = chasing - heat_step
          mode[k] = :heat
        elsif worth_anticipating && desired[k] > chasing + cool_step
          plan[k] = chasing + cool_step
          mode[k] = :cool
        else
          plan[k] = desired[k]
        end

        if mode[k] && mode[k + 1] == mode[k]
          goal[k] = goal[k + 1]
          goal_index[k] = goal_index[k + 1]
        else
          goal[k] = mode[k] ? chasing : plan[k]
          goal_index[k] = mode[k] ? k + 1 : k
        end
      end

      [ plan, mode, goal, goal_index ]
    end

    def forward_pass(targets)
      targets.each_with_index.each_with_object([]) do |(target, k), plan|
        plan << (k.zero? ? target : target.clamp(plan[k - 1] - cool_step, plan[k - 1] + heat_step))
      end
    end
  end
end
