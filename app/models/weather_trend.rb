# Is noticeably warmer or cooler weather coming? Compares today's average air
# temperature with each of the next few days' averages; a change of more than
# THRESHOLD °F counts. Works from a plan's hourly series (rows with :t and :air).
class WeatherTrend
  THRESHOLD = 5.0
  DAYS_AHEAD = 4

  def self.for(series, zone:) = new(series, zone: zone).call

  def initialize(series, zone:)
    @rows = Array(series).map { |r| r.to_h.transform_keys(&:to_sym) }.select { |r| r[:air] }
    @zone = zone
  end

  # :warmer, :cooler, or nil.
  def call
    days = daily_averages
    return if days.size < 2

    today = days.first
    biggest = days.drop(1).first(DAYS_AHEAD).max_by { |avg| (avg - today).abs }
    change = biggest - today
    return if change.abs <= THRESHOLD

    change.positive? ? :warmer : :cooler
  end

  private

  # Average air per local calendar day, starting today (partial days count).
  def daily_averages
    @rows.group_by { |r| Time.zone.parse(r[:t].to_s).in_time_zone(@zone).to_date }
         .sort.map { |_, rows| rows.sum { |r| r[:air].to_f } / rows.size }
  end
end
