module Recommenders
  # raw_target: unrounded °F; target: what to tell the user.
  # details: data for charts/debugging (series of { t:, air:, smoothed_air:, desired:, plan: }).
  Result = Data.define(:raw_target, :reason, :details) do
    def target = raw_target.round
  end
end
