FactoryBot.define do
  # Every user gets a pool on create, so build pools through their user.
  factory :pool do
    transient { user { create(:user) } }

    initialize_with { user.pool }
    to_create(&:save!)

    name { "Backyard" }
    location_name { "Austin, Texas, US" }
    latitude { 30.27 }
    longitude { -97.74 }
    time_zone { "America/Chicago" }
    phone_number { "+15125550100" }

    trait :unlocated do
      latitude { nil }
      longitude { nil }
    end
  end
end
