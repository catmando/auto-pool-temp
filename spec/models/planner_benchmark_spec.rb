require "rails_helper"

# Guards planner quality: the default planner's error on each benchmark
# scenario must be as good as or better than the recorded baseline.
# If you made it better, accept the new scores with `bin/rails planner:record_baseline`.
RSpec.describe PlannerBenchmark do
  benchmark = described_class.new
  baseline = benchmark.baseline.fetch("search")
  scores = benchmark.scores("search")

  it "covers the saved Rochester forecast and the made-up patterns" do
    expect(scores.keys).to include("rochester_2026_10_04", "cold_snap", "heat_wave", "choppy")
    expect(baseline.keys).to match_array(scores.keys)
  end

  scores.each do |scenario, now|
    now.each do |metric, value|
      it "#{scenario}: #{metric} is no worse than the baseline (#{baseline.dig(scenario, metric)}°F)" do
        expect(value).to be <= baseline.dig(scenario, metric) + described_class::TOLERANCE
      end
    end
  end

  it "beats the no-look-ahead baseline planner overall" do
    follow = benchmark.scores("follow")
    expect(scores.values.sum { |s| s["mean_discomfort"] }).to be < follow.values.sum { |s| s["mean_discomfort"] }
  end
end
