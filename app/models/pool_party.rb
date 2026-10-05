# Pool party mode: for a time window, aim warmer than usual. The boost
# (0..+10 °F) replaces the pool's comfort adjustment during the window, and the
# planner works to have the water there when the party *starts*.
class PoolParty < ApplicationRecord
  DEFAULT_START = "12:00"
  BOOSTS = (0..10)

  # A window the planners use: Window.new(starts_at, ends_at, boost).
  Window = Data.define(:starts_at, :ends_at, :boost) do
    def cover?(time) = time >= starts_at && time < ends_at
  end

  belongs_to :pool, touch: true # a new or removed party re-plans

  validates :starts_at, :ends_at, presence: true
  validates :boost, inclusion: { in: BOOSTS }
  validate :ends_after_start

  scope :upcoming, ->(now = Time.current) { where("ends_at > ?", now).order(:starts_at) }

  # From the form: a date plus optional start/end times ("HH:MM", local). The
  # window defaults to noon until midnight; an end at or before the start runs
  # into the next day.
  def self.build_for(pool, date:, start_time: nil, end_time: nil, boost: 5)
    day = Date.parse(date.to_s)
    zone = pool.zone
    starts = at(zone, day, start_time.presence || DEFAULT_START)
    ends = end_time.present? ? at(zone, day, end_time) : zone.local(day.year, day.month, day.day) + 1.day
    ends += 1.day if ends <= starts
    pool.pool_parties.build(starts_at: starts, ends_at: ends, boost: boost)
  rescue Date::Error, ArgumentError
    pool.pool_parties.build(boost: boost).tap { |p| p.errors.add(:base, "Pick a date for the party") }
  end

  def self.at(zone, day, hhmm)
    minutes = PumpSchedule.minutes(hhmm) or raise ArgumentError, "bad time #{hhmm.inspect}"
    zone.local(day.year, day.month, day.day, minutes / 60, minutes % 60)
  end

  def window = Window.new(starts_at, ends_at, boost)

  def label(zone = pool.zone)
    start = starts_at.in_time_zone(zone)
    finish = ends_at.in_time_zone(zone)
    finish_text = finish == finish.beginning_of_day ? "midnight" : finish.strftime("%-l:%M%P").sub(":00", "")
    "#{start.strftime('%a %b %-d, %-l:%M%P').sub(':00', '')} until #{finish_text}"
  end

  private

  def ends_after_start
    errors.add(:ends_at, "must be after the start") if starts_at && ends_at && ends_at <= starts_at
  end
end
