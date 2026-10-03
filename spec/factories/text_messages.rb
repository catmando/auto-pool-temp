FactoryBot.define do
  factory :text_message do
    pool
    direction { "outbound" }
    to { "+15125550100" }
    body { "Set the heater to 88°F." }
    status { "queued" }
  end
end
