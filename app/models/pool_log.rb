# What the owner tells us, logged with what the model expected at the time:
#   water_reading:     a measured water temperature
#   setting_confirmed: "done" after an alert (the heater was set then), maybe with a reading
# Not used by the planner yet; the idea is to tune each pool's model from these.
class PoolLog < ApplicationRecord
  KINDS = %w[water_reading setting_confirmed].freeze
  SOURCES = %w[web sms telegram].freeze

  belongs_to :pool

  validates :kind, inclusion: { in: KINDS }
  validates :source, inclusion: { in: SOURCES }
  validates :logged_at, presence: true
  validates :water_temp, numericality: { in: 32..110 }, allow_nil: true

  scope :recent, -> { order(logged_at: :desc, id: :desc) }

  def self.water_reading!(pool, value, source:, at: Time.current)
    pool.pool_logs.create!(kind: "water_reading", water_temp: value, expected_water_temp: pool.estimated_water_temp(at),
                           source: source, logged_at: at)
  end

  # The owner says they've made the recommended change: assume it happened now.
  def self.confirm_setting!(pool, water_temp: nil, source:, at: Time.current)
    expected = pool.estimated_water_temp(at)
    pool.record_setpoint!(pool.assumed_setpoint, source: "confirmed", at: at) if pool.assumed_setpoint
    pool.pool_logs.create!(kind: "setting_confirmed", setpoint: pool.assumed_setpoint, water_temp: water_temp,
                           expected_water_temp: expected, source: source, logged_at: at)
  end
end
