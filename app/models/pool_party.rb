# Pool party mode: for a time window, aim warmer than usual. The boost
# (0..+10 °F) replaces the pool's comfort adjustment during the window, and the
# planner works to have the water there when the party *starts*.
class PoolParty < ApplicationRecord
  DEFAULT_START_TIME = "12:00"
  DEFAULT_END_TIME = "23:59"
  BOOSTS = (0..10)

  # A window the planners use: Window.new(starts_at, ends_at, boost).
  Window = Data.define(:starts_at, :ends_at, :boost) do
    def cover?(time) = time >= starts_at && time < ends_at
  end

  belongs_to :pool, touch: true # a new, changed, or removed party re-plans

  validates :starts_at, :ends_at, presence: true
  validates :boost, inclusion: { in: BOOSTS }
  validate :ends_after_start

  default_scope { order(:starts_at) }
  scope :upcoming, ->(now = Time.current) { where("ends_at > ?", now) }

  # Form fields: local dates ("2026-10-07") and times ("HH:MM"). The start time
  # defaults to noon; the end defaults to the start date at 11:59 PM.
  def assign_from_form(start_date: nil, start_time: nil, end_date: nil, end_time: nil, boost: self.boost)
    zone = pool.zone
    start_day = Date.parse(start_date.to_s)
    end_day = end_date.present? ? Date.parse(end_date.to_s) : start_day
    self.starts_at = self.class.at(zone, start_day, start_time.presence || DEFAULT_START_TIME)
    self.ends_at = self.class.at(zone, end_day, end_time.presence || DEFAULT_END_TIME)
    self.boost = boost
    self
  rescue Date::Error, ArgumentError
    errors.add(:base, "Pick a date for the party")
    self
  end

  def self.at(zone, day, hhmm)
    minutes = PumpSchedule.minutes(hhmm) or raise ArgumentError, "bad time #{hhmm.inspect}"
    zone.local(day.year, day.month, day.day, minutes / 60, minutes % 60)
  end

  def window = Window.new(starts_at, ends_at, boost)

  # Form values in the pool's time zone.
  def start_date = starts_at&.in_time_zone(pool.zone)&.to_date
  def start_time = starts_at&.in_time_zone(pool.zone)&.strftime("%H:%M") || DEFAULT_START_TIME
  def end_date = ends_at&.in_time_zone(pool.zone)&.to_date
  def end_time = ends_at&.in_time_zone(pool.zone)&.strftime("%H:%M") || DEFAULT_END_TIME

  def label(zone = pool.zone)
    start = starts_at.in_time_zone(zone)
    finish = ends_at.in_time_zone(zone)
    finish_text = finish.to_date == start.to_date ? fmt_time(finish) : "#{finish.strftime('%a %b %-d')}, #{fmt_time(finish)}"
    "#{start.strftime('%a %b %-d')}, #{fmt_time(start)} until #{finish_text}"
  end

  private

  def fmt_time(time) = time.strftime("%-l:%M%P").sub(":00", "")

  def ends_after_start
    errors.add(:ends_at, "must be after the start") if starts_at && ends_at && ends_at <= starts_at
  end
end
