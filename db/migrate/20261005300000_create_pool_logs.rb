class CreatePoolLogs < ActiveRecord::Migration[8.1]
  def change
    # What the owner tells us: water readings and "done, I set it" confirmations,
    # with what the model expected at that moment. Logged for now; later used to
    # tune each pool's model.
    create_table :pool_logs do |t|
      t.references :pool, null: false, foreign_key: true
      t.string :kind, null: false # "water_reading" / "setting_confirmed"
      t.datetime :logged_at, null: false
      t.decimal :water_temp, precision: 5, scale: 2 # reported, if any
      t.decimal :expected_water_temp, precision: 5, scale: 2 # the model's estimate then
      t.integer :setpoint # heater setting confirmed, if any
      t.string :source, null: false # "web" / "sms" / "telegram"
      t.timestamps
    end
    add_index :pool_logs, %i[pool_id logged_at]
  end
end
