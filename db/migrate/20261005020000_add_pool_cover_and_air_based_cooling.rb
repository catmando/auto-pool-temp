class AddPoolCoverAndAirBasedCooling < ActiveRecord::Migration[8.1]
  def up
    change_table :pools, bulk: true do |t|
      t.boolean :has_cover, null: false, default: false
      # What we believe right now (like assumed_setpoint): is the cover on?
      t.boolean :cover_on, null: false, default: true
      # Multiplies the standard heat-loss/gain model (PoolEnvironment). 1 = standard.
      t.decimal :cooling_factor, precision: 4, scale: 2, null: false, default: 1
      t.remove :cool_rate_per_hour
    end
  end

  def down
    change_table :pools, bulk: true do |t|
      t.decimal :cool_rate_per_hour, precision: 5, scale: 3, null: false, default: 0.1
      t.remove :has_cover, :cover_on, :cooling_factor
    end
  end
end
