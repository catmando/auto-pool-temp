class AddComfortAdjustmentAndPoolParties < ActiveRecord::Migration[8.1]
  def up
    # "I like it warmer/cooler": degrees added to the ideal, -10..+10.
    add_column :pools, :comfort_adjustment, :integer, null: false, default: 0

    # New default curve: 95°F air -> 75°F pool, 35°F air -> 98°F pool.
    change_column_default :pools, :hot_pool_temp, from: 80, to: 75
    change_column_default :pools, :cold_pool_temp, from: 102, to: 98
    execute "UPDATE pools SET hot_pool_temp = 75, cold_pool_temp = 98 " \
            "WHERE hot_air_temp = 95 AND hot_pool_temp = 80 AND cold_air_temp = 35 AND cold_pool_temp = 102"

    # Pool party: a warmer target (0..+10 instead of the comfort adjustment) for a time window.
    create_table :pool_parties do |t|
      t.references :pool, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :boost, null: false, default: 5
      t.timestamps
    end
    add_index :pool_parties, %i[pool_id starts_at]
  end

  def down
    drop_table :pool_parties
    change_column_default :pools, :cold_pool_temp, from: 98, to: 102
    change_column_default :pools, :hot_pool_temp, from: 75, to: 80
    remove_column :pools, :comfort_adjustment
  end
end
