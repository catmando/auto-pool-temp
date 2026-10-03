require "rails_helper"
require_relative "shared_examples"

RSpec.describe Recommenders::Lookahead do
  it_behaves_like "a recommender"

  let(:curve) { TargetCurve.new(hot_air: 95, hot_pool: 80, cold_air: 35, cold_pool: 102) }
  let(:now) { Time.utc(2026, 10, 1, 12) }

  def recommend(forecast, heat: 3, cool: 2, next_check_at: now + 12.hours)
    described_class.new(forecast: forecast, curve: curve, heat_rate: heat, cool_rate: cool,
                        now: now, next_check_at: next_check_at).call
  end

  # Air drops 65 -> 35 at +cold_at hours: ideal pool goes 91 -> 102 (+11°F).
  # At 3°F/day that takes ~3.7 days, so heating must start well before.
  describe "a cold snap ahead" do
    it "waits while there is still time" do
      result = recommend(step_forecast(before: 65, after: 35, at_hour: 6 * 24, start: now))
      expect(result.target).to eq(91)
      expect(result.details[:urgent_mode]).to be_nil
    end

    it "tells you to start heating once it can't wait until the next check" do
      result = recommend(step_forecast(before: 65, after: 35, at_hour: 3 * 24, start: now))
      expect(result.target).to eq(102)
      expect(result.details[:urgent_mode]).to eq("heat")
      expect(result.reason).to match(/102°F by .*3°F\/day it has to start heating now/)
    end

    it "is more urgent for a slower-heating pool" do
      forecast = step_forecast(before: 65, after: 35, at_hour: 5 * 24, start: now)
      expect(recommend(forecast, heat: 4).target).to eq(91)
      expect(recommend(forecast, heat: 2).target).to eq(102)
    end

    it "acts sooner when the next check is further away" do
      forecast = step_forecast(before: 65, after: 35, at_hour: 4 * 24, start: now)
      expect(recommend(forecast, next_check_at: now + 1.hour).target).to eq(91)
      expect(recommend(forecast, next_check_at: now + 24.hours).target).to eq(102)
    end
  end

  describe "a heat wave ahead" do
    # 65 -> 95 air: ideal pool 91 -> 80 (-11°F); at 2°F/day that's ~5.5 days.
    it "tells you to turn it down early" do
      result = recommend(step_forecast(before: 65, after: 95, at_hour: 4 * 24, start: now))
      expect(result.target).to eq(80)
      expect(result.details[:urgent_mode]).to eq("cool")
      expect(result.reason).to include("start cooling now")
    end

    it "waits when the heat is far enough off" do
      result = recommend(step_forecast(before: 65, after: 95, at_hour: 9 * 24, start: now))
      expect(result.target).to eq(91)
    end
  end

  describe "returning to mild weather" do
    it "keeps the pool warm through a cold snap instead of pre-cooling for its end" do
      result = recommend(step_forecast(before: 35, after: 65, at_hour: 24, start: now))
      expect(result.target).to eq(102)
      expect(result.details[:urgent_mode]).to be_nil
    end

    it "keeps the pool cool through a heat wave instead of pre-heating for its end" do
      result = recommend(step_forecast(before: 95, after: 65, at_hour: 24, start: now))
      expect(result.target).to eq(80)
      expect(result.details[:urgent_mode]).to be_nil
    end
  end

  describe "the plan" do
    # Two-day cold snap starting in three days, then back to normal.
    let(:forecast) do
      hourly_forecast(start: now) { |h| (3 * 24...5 * 24).cover?(h) ? 35 : 65 }
    end
    let(:plan) { recommend(forecast).details[:series].map { |r| r[:plan] } }

    it "never changes faster than the pool can" do
      plan.each_cons(2) do |a, b|
        expect(b - a).to be <= (3 / 24.0) + 0.11
        expect(a - b).to be <= (2 / 24.0) + 0.11
      end
    end

    it "ends on the ideal temperature" do
      expect(plan.last).to be_within(0.1).of(91)
    end

    def row_at(hours) = recommend(forecast).details[:series].find { |r| Time.zone.parse(r[:t]) == now + hours.hours }

    it "runs warmer than ideal before the snap so it's ready in time" do
      expect(row_at(60)[:plan]).to be > row_at(60)[:desired] + 1
    end

    it "is on target during the snap" do
      expect(row_at(108)[:plan]).to be_within(0.5).of(102)
    end

    it "runs warmer than ideal after the snap while it cools off" do
      expect(row_at(150)[:plan]).to be > row_at(150)[:desired] + 1
    end

    it "lets a later, bigger swing win when two conflict" do
      conflict = hourly_forecast(start: now) { |h| (3 * 24...5 * 24).cover?(h) ? 35 : (h >= 5 * 24 ? 105 : 65) }
      series = recommend(conflict).details[:series]
      snap = series.find { |r| Time.zone.parse(r[:t]) == now + 108.hours }
      expect(snap[:plan]).to be < snap[:desired] - 5
    end
  end
end
