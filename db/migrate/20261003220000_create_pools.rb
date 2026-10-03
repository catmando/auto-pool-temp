class CreatePools < ActiveRecord::Migration[8.1]
  def change
    create_table :pools do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :name, null: false, default: "My Pool"

      # Location
      t.string :location_name
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      t.string :time_zone, null: false, default: "UTC"

      # Target curve: two anchor points (air temp -> pool temp), °F
      t.decimal :hot_air_temp, precision: 5, scale: 1, null: false, default: 95
      t.decimal :hot_pool_temp, precision: 5, scale: 1, null: false, default: 80
      t.decimal :cold_air_temp, precision: 5, scale: 1, null: false, default: 35
      t.decimal :cold_pool_temp, precision: 5, scale: 1, null: false, default: 102

      # How fast the pool can change, °F per day
      t.decimal :heat_rate_per_day, precision: 5, scale: 2, null: false, default: 3
      t.decimal :cool_rate_per_day, precision: 5, scale: 2, null: false, default: 2

      # Notifications
      t.string :phone_number
      t.integer :checks_per_day, null: false, default: 2
      t.integer :min_change, null: false, default: 1
      t.boolean :notifications_enabled, null: false, default: true

      # Algorithm selection
      t.string :strategy, null: false, default: "lookahead"
      t.integer :forecast_days, null: false, default: 10

      # What we believe the heater is set to right now
      t.integer :assumed_setpoint
      t.string :setpoint_source # "recommended", "user_reported", "initial"
      t.datetime :setpoint_updated_at

      t.datetime :last_checked_at
      t.timestamps
    end
    add_index :pools, :phone_number

    create_table :recommendations do |t|
      t.references :pool, null: false, foreign_key: true
      t.string :strategy, null: false
      t.integer :target_temp, null: false
      t.decimal :raw_target, precision: 6, scale: 2
      t.integer :assumed_setpoint
      t.text :reason
      t.boolean :notified, null: false, default: false
      t.json :details
      t.timestamps
    end

    create_table :text_messages do |t|
      t.references :pool, foreign_key: true
      t.string :direction, null: false # "outbound" / "inbound"
      t.string :to
      t.string :from
      t.text :body, null: false
      t.string :provider_sid
      t.string :status
      t.text :error
      t.timestamps
    end
  end
end
