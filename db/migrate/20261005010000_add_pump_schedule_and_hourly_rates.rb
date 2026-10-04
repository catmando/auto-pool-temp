class AddPumpScheduleAndHourlyRates < ActiveRecord::Migration[8.1]
  def up
    change_table :pools, bulk: true do |t|
      # The heater only runs while the pump does. One or two daily windows, "HH:MM" local time.
      t.string :pump_on_1, null: false, default: "04:00"
      t.string :pump_off_1, null: false, default: "10:00"
      t.string :pump_on_2, default: "16:00"
      t.string :pump_off_2, default: "22:00"
      # Rates are now °F per hour.
      t.decimal :heat_rate_per_hour, precision: 5, scale: 3, null: false, default: 2
      t.decimal :cool_rate_per_hour, precision: 5, scale: 3, null: false, default: 0.1
      t.remove :heat_rate_per_day, :cool_rate_per_day
    end
  end

  def down
    change_table :pools, bulk: true do |t|
      t.decimal :heat_rate_per_day, precision: 5, scale: 2, null: false, default: 3
      t.decimal :cool_rate_per_day, precision: 5, scale: 2, null: false, default: 2
      t.remove :pump_on_1, :pump_off_1, :pump_on_2, :pump_off_2, :heat_rate_per_hour, :cool_rate_per_hour
    end
  end
end
