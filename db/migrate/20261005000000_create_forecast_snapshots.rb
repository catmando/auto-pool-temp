class CreateForecastSnapshots < ActiveRecord::Migration[8.1]
  def change
    # Saved forecasts for test mode: plan against fixed data while tuning.
    create_table :forecast_snapshots do |t|
      t.references :pool, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :taken_at, null: false # "now" when planning against this snapshot
      t.string :time_zone, null: false
      t.decimal :water_temp, precision: 5, scale: 2 # water estimate at taken_at
      t.json :points, null: false # [[epoch_seconds, air_temp_f], ...] hourly
      t.timestamps
    end
    add_reference :pools, :test_snapshot, foreign_key: { to_table: :forecast_snapshots, on_delete: :nullify }
  end
end
