class AddSchedulePlanning < ActiveRecord::Migration[8.1]
  def up
    change_table :pools, bulk: true do |t|
      # Above this air temp a slightly cooler pool feels comfortable; below it, a slightly warmer one does.
      t.decimal :warm_day_threshold, precision: 5, scale: 1, null: false, default: 80

      # Best guess of the actual water temperature, advanced by simulation.
      t.decimal :water_temp, precision: 5, scale: 2
      t.datetime :water_temp_at
      t.string :water_temp_source # "reported" / "estimated"
    end

    change_column_default :pools, :strategy, from: "lookahead", to: "search"
    change_column_default :pools, :forecast_days, from: 10, to: 16
    change_column_default :pools, :notification_channel, from: "sms", to: "telegram"
    execute "UPDATE pools SET strategy = 'search' WHERE strategy IN ('lookahead', 'linear')"
    execute "UPDATE pools SET forecast_days = 16"
    # Telegram only for now (SMS needs A2P registration).
    execute "UPDATE pools SET notification_channel = 'telegram'"
  end

  def down
    change_table :pools, bulk: true do |t|
      t.remove :warm_day_threshold, :water_temp, :water_temp_at, :water_temp_source
    end
    change_column_default :pools, :strategy, from: "search", to: "lookahead"
    change_column_default :pools, :forecast_days, from: 16, to: 10
    change_column_default :pools, :notification_channel, from: "telegram", to: "sms"
    execute "UPDATE pools SET strategy = 'lookahead' WHERE strategy IN ('search', 'follow')"
  end
end
