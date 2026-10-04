namespace :planner do
  desc "Score every planner on the benchmark scenarios, against the recorded baseline"
  task benchmark: :environment do
    benchmark = PlannerBenchmark.new
    baseline = benchmark.baseline
    benchmark.all_scores.each do |strategy, scores|
      puts strategy
      scores.each do |scenario, now|
        was = baseline.dig(strategy, scenario) || {}
        line = now.map do |metric, value|
          old = was[metric]
          change = old ? format(" (%+.2f)", value - old) : " (new)"
          "#{metric} #{format('%.2f', value)}#{change}"
        end
        puts "  #{scenario.ljust(26)} #{line.join('   ')}"
      end
    end
  end

  desc "Accept the current planner scores as the benchmark baseline"
  task record_baseline: :environment do
    PlannerBenchmark.new.record_baseline!
    puts "Wrote #{PlannerBenchmark::BASELINE_PATH.relative_path_from(Rails.root)}"
  end
end
