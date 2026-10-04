class Pool < ApplicationRecord
  # Local hours at which scheduled checks run, by checks_per_day.
  CHECK_HOURS = { 1 => [ 7 ], 2 => [ 7, 17 ], 3 => [ 7, 13, 19 ] }.freeze
  # Plan as far ahead as the forecast goes (Open-Meteo: 16 days).
  FORECAST_DAYS = 16

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
  validates :warm_day_threshold, numericality: { in: 40..110 }
  validates :min_change, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :forecast_days, numericality: { only_integer: true, in: 1..16 }
  validates :strategy, inclusion: { in: ->(_) { Recommenders.keys } }
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validates :phone_number, format: { with: /\A\+\d{10,15}\z/, message: "must be a valid phone number" }, allow_nil: true
  validates :assumed_setpoint, numericality: { only_integer: true, in: 40..110 }, allow_nil: true
  validates :notification_channel, inclusion: { in: Notifications.channels }
  validate :time_zone_exists
  validate :anchors_distinct

  # A changed phone number must be confirmed again.
  before_save :reset_phone_verification, if: -> { will_save_change_to_phone_number? && !will_save_change_to_phone_verified_at? }

  def located? = latitude.present? && longitude.present?

  def phone_verified? = phone_number.present? && phone_verified_at.present?

  def telegram_linked? = telegram_chat_id.present?

  # Is the address for the chosen channel confirmed?
  def contact_verified?
    notification_channel == "telegram" ? telegram_linked? : phone_verified?
  end

  def notifiable? = notifications_enabled? && contact_verified?

  def channel_label = Notifications.label(notification_channel)

  def zone = ActiveSupport::TimeZone[time_zone] || Time.zone

  def check_hours = CHECK_HOURS.fetch(checks_per_day)

  # Is a scheduled check due at +time+? True once a scheduled check time has
  # passed without a check since, so checks missed while the machine was
  # asleep or offline run at the next opportunity.
  def due?(time = Time.current)
    return false unless located?

    last_checked_at.nil? || last_checked_at < last_scheduled_check_at(time)
  end

  def last_scheduled_check_at(time)
    local = time.in_time_zone(zone)
    [ 0, 1 ].each do |days_back|
      day = local.to_date - days_back
      check_hours.reverse_each do |hour|
        candidate = zone.local(day.year, day.month, day.day, hour)
        return candidate if candidate <= time
      end
    end
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

  # All scheduled check times in (from, to] — when the heater setting can change.
  def check_times_between(from, to)
    times = []
    day = from.in_time_zone(zone).to_date
    while (start = zone.local(day.year, day.month, day.day)) <= to
      check_hours.each do |hour|
        time = start + hour.hours
        times << time if time > from && time <= to
      end
      day += 1
    end
    times
  end

  # Best estimate of the actual water temperature at +time+: the last known
  # value, moved toward the heater setpoint at the pool's heat/cool rates.
  def estimated_water_temp(time = Time.current)
    return assumed_setpoint&.to_f if water_temp.nil?

    PoolPhysics.for(self).advance(water_temp.to_f, assumed_setpoint, (time - (water_temp_at || time)) / 3600.0)
  end

  def record_water_temp!(value, source: "reported", at: Time.current)
    update!(water_temp: value, water_temp_at: at, water_temp_source: source)
  end

  def needs_change?(target)
    assumed_setpoint.nil? || (target - assumed_setpoint).abs >= min_change
  end

  # Before the setpoint changes, bank the water temp reached under the old one.
  def record_setpoint!(value, source:, at: Time.current)
    estimate = estimated_water_temp(at)
    attrs = { assumed_setpoint: value, setpoint_source: source, setpoint_updated_at: at }
    attrs.merge!(water_temp: estimate, water_temp_at: at, water_temp_source: water_temp_at == at ? water_temp_source : "estimated") if estimate
    update!(attrs)
  end

  def recommender_class = Recommenders.for(strategy)

  private

  def reset_phone_verification
    self.phone_verified_at = nil
    self.phone_verification_digest = nil
    self.phone_verification_sent_at = nil
    self.phone_verification_attempts = 0
  end

  def time_zone_exists
    errors.add(:time_zone, "is not a known time zone") unless ActiveSupport::TimeZone[time_zone.to_s]
  end

  def anchors_distinct
    if hot_air_temp.present? && hot_air_temp == cold_air_temp
      errors.add(:hot_air_temp, "must differ from the cold air temperature")
    end
  end
end
