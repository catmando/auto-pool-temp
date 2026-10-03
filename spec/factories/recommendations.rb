FactoryBot.define do
  factory :recommendation do
    pool
    strategy { "lookahead" }
    target_temp { 88 }
    raw_target { 88.2 }
    reason { "Because." }
    details do
      { "series" => (0..47).map { |h|
        { "t" => (Time.utc(2026, 10, 1) + h.hours).iso8601, "air" => 70, "smoothed_air" => 70, "desired" => 88, "plan" => 88 }
      } }
    end
  end
end
