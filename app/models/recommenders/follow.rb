module Recommenders
  # Baseline: at each check, set the heater to the ideal for the period until
  # the next check. Never plans ahead, so it's always playing catch-up.
  class Follow < SchedulePlanner
    def self.label = "Follow"
    def self.description = "Set each check to that period's ideal. No planning ahead."

    private

    def choose_setpoints = stages.map { |s| stage_ideal(s).round }
  end
end
