# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_05_020000) do
  create_table "forecast_snapshots", force: :cascade do |t|
    t.integer "pool_id", null: false
    t.string "name", null: false
    t.datetime "taken_at", null: false
    t.string "time_zone", null: false
    t.decimal "water_temp", precision: 5, scale: 2
    t.json "points", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pool_id"], name: "index_forecast_snapshots_on_pool_id"
  end

  create_table "pools", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", default: "My Pool", null: false
    t.string "location_name"
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.string "time_zone", default: "UTC", null: false
    t.decimal "hot_air_temp", precision: 5, scale: 1, default: "95.0", null: false
    t.decimal "hot_pool_temp", precision: 5, scale: 1, default: "80.0", null: false
    t.decimal "cold_air_temp", precision: 5, scale: 1, default: "35.0", null: false
    t.decimal "cold_pool_temp", precision: 5, scale: 1, default: "102.0", null: false
    t.string "phone_number"
    t.integer "checks_per_day", default: 2, null: false
    t.integer "min_change", default: 1, null: false
    t.boolean "notifications_enabled", default: true, null: false
    t.string "strategy", default: "search", null: false
    t.integer "forecast_days", default: 16, null: false
    t.integer "assumed_setpoint"
    t.string "setpoint_source"
    t.datetime "setpoint_updated_at"
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "notification_channel", default: "telegram", null: false
    t.datetime "phone_verified_at"
    t.string "phone_verification_digest"
    t.datetime "phone_verification_sent_at"
    t.integer "phone_verification_attempts", default: 0, null: false
    t.string "telegram_chat_id"
    t.datetime "telegram_linked_at"
    t.string "telegram_link_token"
    t.datetime "telegram_link_sent_at"
    t.decimal "warm_day_threshold", precision: 5, scale: 1, default: "80.0", null: false
    t.decimal "water_temp", precision: 5, scale: 2
    t.datetime "water_temp_at"
    t.string "water_temp_source"
    t.integer "test_snapshot_id"
    t.string "pump_on_1", default: "04:00", null: false
    t.string "pump_off_1", default: "10:00", null: false
    t.string "pump_on_2", default: "16:00"
    t.string "pump_off_2", default: "22:00"
    t.decimal "heat_rate_per_hour", precision: 5, scale: 3, default: "2.0", null: false
    t.boolean "has_cover", default: false, null: false
    t.boolean "cover_on", default: true, null: false
    t.decimal "cooling_factor", precision: 4, scale: 2, default: "1.0", null: false
    t.index ["phone_number"], name: "index_pools_on_phone_number"
    t.index ["telegram_chat_id"], name: "index_pools_on_telegram_chat_id"
    t.index ["telegram_link_token"], name: "index_pools_on_telegram_link_token", unique: true
    t.index ["test_snapshot_id"], name: "index_pools_on_test_snapshot_id"
    t.index ["user_id"], name: "index_pools_on_user_id", unique: true
  end

  create_table "recommendations", force: :cascade do |t|
    t.integer "pool_id", null: false
    t.string "strategy", null: false
    t.integer "target_temp", null: false
    t.decimal "raw_target", precision: 6, scale: 2
    t.integer "assumed_setpoint"
    t.text "reason"
    t.boolean "notified", default: false, null: false
    t.json "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pool_id"], name: "index_recommendations_on_pool_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "text_messages", force: :cascade do |t|
    t.integer "pool_id"
    t.string "direction", null: false
    t.string "to"
    t.string "from"
    t.text "body", null: false
    t.string "provider_sid"
    t.string "status"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "channel", default: "sms", null: false
    t.index ["pool_id"], name: "index_text_messages_on_pool_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "forecast_snapshots", "pools"
  add_foreign_key "pools", "forecast_snapshots", column: "test_snapshot_id", on_delete: :nullify
  add_foreign_key "pools", "users"
  add_foreign_key "recommendations", "pools"
  add_foreign_key "sessions", "users"
  add_foreign_key "text_messages", "pools"
end
