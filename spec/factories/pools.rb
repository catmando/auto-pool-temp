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
    # A fixed curve (95->80, 35->102: 91°F ideal at 65°F air) so specs don't depend on the app defaults.
    hot_pool_temp { 80 }
    cold_pool_temp { 102 }
    phone_number { "+15125550100" }
    phone_verified_at { Time.current }
    # SMS stays supported in the backend; most specs exercise it. See :telegram.
    notification_channel { "sms" }

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
