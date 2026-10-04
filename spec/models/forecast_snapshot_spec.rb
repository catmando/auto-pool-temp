require "rails_helper"

RSpec.describe ForecastSnapshot do
  let(:pool) { create(:pool, assumed_setpoint: 90) }

  it "saves the live forecast with the water estimate" do
    freeze_time do
      snapshot = described_class.capture!(pool)
      expect(snapshot).to have_attributes(taken_at: Time.current, water_temp: 90, time_zone: "UTC")
      expect(snapshot.name).to start_with("Austin, Texas, US, ")
      expect(snapshot.forecast.points.size).to eq(flat_forecast(65).points.size)
      expect(snapshot.forecast.temp_at(Time.current)).to eq(65)
    end
  end

  it "rebuilds the forecast behind a past plan" do
    check = PoolCheck.call(pool, notify: false, weather: FakeWeather.new(forecast: step_forecast(before: 70, after: 50, at_hour: 30)))
    snapshot = described_class.from_recommendation!(check.recommendation, name: "Before the cold")
    expect(snapshot.name).to eq("Before the cold")
    expect(snapshot.taken_at).to eq(Time.zone.parse(check.recommendation.series.first["t"]))
    expect(snapshot.forecast.temp_at(snapshot.taken_at + 40.hours)).to eq(50)
    expect(snapshot.water_temp).to eq(90)
  end

  it "refuses a plan with no forecast data" do
    expect { described_class.from_recommendation!(create(:recommendation, pool: pool, details: {})) }.to raise_error(ArgumentError)
  end
end

RSpec.describe PoolCheck, "in test mode" do
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 80) }
  let!(:snapshot) do
    ForecastSnapshot.create!(pool: pool, name: "Frozen", taken_at: Time.utc(2026, 10, 4, 15), time_zone: "UTC", water_temp: 88,
                             points: (0...(10 * 24)).map { |h| [ (Time.utc(2026, 10, 4) + h.hours).to_i, 65.0 ] })
  end

  before { pool.update!(test_snapshot: snapshot) }

  it "plans with the saved forecast, as of when it was saved" do
    check = PoolCheck.call(pool, weather: FakeWeather.new.tap { |w| w.error = Weather::OpenMeteo::Error.new("not used") })
    expect(check.recommendation.target_temp).to eq(91)
    expect(check.recommendation.details["water_now"]).to eq(88)
    expect(check.recommendation.series.first["t"]).to eq("2026-10-04T15:00:00Z")
    expect(check.recommendation.details["test_snapshot_name"]).to eq("Frozen")
  end

  it "never sends alerts or counts as a scheduled check" do
    check = PoolCheck.call(pool)
    expect(check).not_to be_notified
    expect(TelegramBot.sender.deliveries).to be_empty
    expect(pool.reload.last_checked_at).to be_nil
  end

  it "is skipped by the scheduler" do
    expect { ScheduledChecksJob.perform_now(Time.current) }.not_to have_enqueued_job(PoolCheckJob)
  end
end
