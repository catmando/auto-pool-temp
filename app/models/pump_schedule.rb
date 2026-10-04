# When the pool pump runs each day. The heater can only run while the pump
# does. Windows are [on, off] times of day ("HH:MM", local); one may run past
# midnight (e.g. 22:00-02:00). No windows means the pump always runs.
class PumpSchedule
  TIME_FORMAT = /\A([01]?\d|2[0-3]):([0-5]\d)\z/
  SAMPLE_MINUTES = 5

  attr_reader :windows

  def self.minutes(text)
    match = text.to_s.strip.match(TIME_FORMAT) or return
    match[1].to_i * 60 + match[2].to_i
  end

  def self.always_on = new([])

  # +windows+: [["04:00", "10:00"], ...]; incomplete or empty windows are skipped.
  def initialize(windows, time_zone: "UTC")
    @zone = ActiveSupport::TimeZone[time_zone] || Time.zone
    @windows = windows.filter_map do |on, off|
      on, off = self.class.minutes(on), self.class.minutes(off)
      [ on, off ] if on && off && on != off
    end
  end

  def always_on? = windows.empty?

  def on_at?(time)
    return true if always_on?

    local = time.in_time_zone(@zone)
    minute = local.hour * 60 + local.min
    windows.any? { |on, off| on < off ? minute >= on && minute < off : minute >= on || minute < off }
  end

  # Share of the hour starting at +time+ that the pump runs (0.0-1.0).
  def on_fraction(time)
    return 1.0 if always_on?

    samples = 60 / SAMPLE_MINUTES
    (0...samples).count { |i| on_at?(time + (i * SAMPLE_MINUTES + SAMPLE_MINUTES / 2.0).minutes) }.fdiv(samples)
  end

  def hours_per_day = always_on? ? 24.0 : (0...24).sum { |h| on_fraction(@zone.local(2026, 1, 1) + h.hours) }

  def describe
    return "always on" if always_on?

    windows.map { |on, off| "#{fmt(on)}–#{fmt(off)}" }.join(" and ")
  end

  private

  def fmt(minutes) = Time.utc(2000, 1, 1, minutes / 60, minutes % 60).strftime("%-l:%M%P").sub(":00", "")
end
