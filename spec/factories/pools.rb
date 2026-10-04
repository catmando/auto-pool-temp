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
    phone_verified_at { Time.current }

    trait :unverified do
      phone_verified_at { nil }
    end

    trait :telegram do
      notification_channel { "telegram" }
      telegram_chat_id { "424242" }
      telegram_linked_at { Time.current }
    end

    trait :unlocated do
      latitude { nil }
      longitude { nil }
    end
  end
end
