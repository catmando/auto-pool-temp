class Pool < ApplicationRecord
  # Local hours at which scheduled checks run, by checks_per_day.
  CHECK_HOURS = { 1 => [ 7 ], 2 => [ 7, 17 ], 3 => [ 7, 13, 19 ] }.freeze

  belongs_to :user
  has_many :recommendations, dependent: :destroy
  has_many :text_messages, dependent: :nullify

  normalizes :phone_number, with: ->(raw) {
    digits = raw.to_s.gsub(/\D/, "")
    if digits.empty? then nil
    elsif digits.length == 10 then "+1#{digits}"
    else "+#{digits}"
    end
  }

  validates :name, presence: true
  validates :hot_air_temp, :hot_pool_temp, :cold_air_temp, :cold_pool_temp, numericality: true
  validates :heat_rate_per_day, :cool_rate_per_day, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :checks_per_day, inclusion: { in: CHECK_HOURS.keys }
  validates :min_change, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :forecast_days, numericality: { only_integer: true, in: 1..16 }
  validates :strategy, inclusion: { in: ->(_) { Recommenders.keys } }
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validates :phone_number, format: { with: /\A\+\d{10,15}\z/, message: "must be a valid phone number" }, allow_nil: true
  validates :assumed_setpoint, numericality: { only_integer: true, in: 40..110 }, allow_nil: true
  validate :time_zone_exists
  validate :anchors_distinct

  def located? = latitude.present? && longitude.present?

  def zone = ActiveSupport::TimeZone[time_zone] || Time.zone

  def check_hours = CHECK_HOURS.fetch(checks_per_day)

  # Is a scheduled check due at +time+ (and not already done this hour)?
  def due?(time = Time.current)
    local = time.in_time_zone(zone)
    return false unless located? && check_hours.include?(local.hour)

    last_checked_at.nil? || last_checked_at < local.beginning_of_hour
  end

  def next_check_after(time)
    local = time.in_time_zone(zone)
    (0..1).each do |day_offset|
      day = local.to_date + day_offset
      check_hours.each do |hour|
        candidate = zone.local(day.year, day.month, day.day, hour)
        return candidate if candidate > time
      end
    end
  end

  def needs_change?(target)
    assumed_setpoint.nil? || (target - assumed_setpoint).abs >= min_change
  end

  def record_setpoint!(value, source:, at: Time.current)
    update!(assumed_setpoint: value, setpoint_source: source, setpoint_updated_at: at)
  end

  def recommender_class = Recommenders.for(strategy)

  private

  def time_zone_exists
    errors.add(:time_zone, "is not a known time zone") unless ActiveSupport::TimeZone[time_zone.to_s]
  end

  def anchors_distinct
    if hot_air_temp.present? && hot_air_temp == cold_air_temp
      errors.add(:hot_air_temp, "must differ from the cold air temperature")
    end
  end
end
