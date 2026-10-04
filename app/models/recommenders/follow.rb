module Recommenders
  # Baseline: at each check, set the heater to the ideal for the period until
  # the next check, and take the cover off (if there is one) only when the
  # water is more than a degree too warm. Never plans ahead.
  class Follow < SchedulePlanner
    def self.label = "Follow"
    def self.description = "Set each check to that period's ideal. No planning ahead."

    private

    def choose_decisions
      temp = start_temp
      stages.map do |stage|
        ideal = stage_ideal(stage)
        decision = Decision.new(ideal.round, has_cover && temp <= ideal + 1)
        temp = run_stage(stage, temp, decision)
        decision
      end
    end
  end
end
