class AddPumpBoost < ActiveRecord::Migration[8.1]
  def change
    change_table :pools, bulk: true do |t|
      # Recommend running the pump outside its normal hours only when, even heating flat out on the
      # normal schedule, the water would fall more than this many °F short of the ideal.
      t.decimal :pump_boost_threshold, precision: 4, scale: 1, null: false, default: 3
      # What we believe right now (like cover_on): is the pump running around the clock?
      t.boolean :pump_extended, null: false, default: false
    end
  end
end
