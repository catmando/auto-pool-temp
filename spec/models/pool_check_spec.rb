require "rails_helper"

RSpec.describe PoolCheck do
  let(:pool) { create(:pool, assumed_setpoint: 85, setpoint_source: "user_reported") }
  let(:weather) { FakeWeather.new(forecast: flat_forecast(65, time_zone: "America/Chicago")) }
  let(:sender) { FakeSmsSender.new }
  let(:now) { Time.current }

  def check(**options) = described_class.call(pool, weather: weather, sender: sender, now: now, **options)

  it "fetches the forecast for the pool's location" do
    check
    expect(weather.requests).to eq([ { latitude: pool.latitude, longitude: pool.longitude, days: 16 } ])
  end

  it "records a recommendation" do
    result = check
    expect(result.recommendation).to have_attributes(strategy: "search", assumed_setpoint: 85)
    expect(result.recommendation.target_temp).to be_between(91, 92) # ideal 91, a degree more covers pump-off losses
    expect(result.recommendation.reason).to include("91°F")
    expect(result.recommendation.series).not_to be_empty
  end

  it "uses the pool's chosen strategy" do
    pool.update!(strategy: "follow")
    expect(check.recommendation.strategy).to eq("follow")
  end

  context "when the setting should change" do
    it "texts the user, stating the assumption" do
      check
      expect(sender.deliveries.size).to eq(1)
      body = sender.deliveries.first[:body]
      expect(body).to include("Your heater should be set to: #{pool.recommendations.last.target_temp}°F",
                              "Respond with current pool temperature to improve system accuracy.")
      expect(body).not_to include("Why", "Coming up")
    end

    it "assumes the user follows the advice" do
      result = check
      expect(result).to be_notified
      expect(pool.reload).to have_attributes(assumed_setpoint: result.recommendation.target_temp, setpoint_source: "recommended")
    end

    it "keeps the old assumption if the text fails" do
      sender.fail_with = "nope"
      result = check
      expect(result).not_to be_notified
      expect(result.text_message).to be_failed
      expect(pool.reload.assumed_setpoint).to eq(85)
    end
  end

  context "when nothing needs to change" do
    # Settle on whatever the plan says now, so the next check has nothing to change.
    before do
      3.times { pool.update!(assumed_setpoint: described_class.call(pool, weather: weather, notify: false).recommendation.target_temp) }
    end

    it "doesn't text" do
      result = check
      expect(sender.deliveries).to be_empty
      expect(result).not_to be_notified
    end
  end

  context "when the current setting is unknown" do
    before { pool.update!(assumed_setpoint: nil) }

    it "texts and asks for confirmation" do
      check
      expect(sender.deliveries.first[:body]).to end_with("Respond with current pool temperature to improve system accuracy.")
    end
  end

  it "doesn't text or touch the setpoint in preview mode" do
    result = check(notify: false)
    expect(sender.deliveries).to be_empty
    expect(result.recommendation).to be_persisted
    expect(pool.reload).to have_attributes(assumed_setpoint: 85, last_checked_at: nil)
  end

  it "doesn't text when alerts are paused" do
    pool.update!(notifications_enabled: false)
    check
    expect(sender.deliveries).to be_empty
  end

  it "doesn't text without a phone number" do
    pool.update!(phone_number: nil)
    check
    expect(sender.deliveries).to be_empty
  end

  it "stamps the check time" do
    freeze_time do
      check
      expect(pool.reload.last_checked_at).to eq(Time.current)
    end
  end

  it "adopts the forecast's time zone" do
    pool.update!(time_zone: "UTC")
    check
    expect(pool.reload.time_zone).to eq("America/Chicago")
  end

  it "ignores unknown forecast time zones" do
    weather.forecast_result = flat_forecast(65, time_zone: "Bogus/Zone")
    check
    expect(pool.reload.time_zone).to eq("America/Chicago")
  end

  it "refuses to run without a location" do
    pool.update!(latitude: nil, longitude: nil)
    expect { check }.to raise_error(ArgumentError, /no location/)
  end

  it "lets weather errors propagate (jobs retry them)" do
    weather.error = Weather::OpenMeteo::Error.new("down")
    expect { check }.to raise_error(Weather::OpenMeteo::Error)
  end

  it "uses the app-wide weather provider and sender by default" do
    described_class.call(pool)
    expect(Weather.provider.requests.size).to eq(1)
    expect(Sms.sender.deliveries.size).to eq(1)
  end
end

RSpec.describe PoolCheck, "channels" do
  let(:weather) { FakeWeather.new(forecast: flat_forecast(65)) }

  it "doesn't alert an unconfirmed phone" do
    pool = create(:pool, :unverified)
    check = described_class.call(pool, weather: weather)
    expect(check).not_to be_notified
    expect(Sms.sender.deliveries).to be_empty
  end

  it "alerts a linked Telegram chat" do
    pool = create(:pool, :telegram)
    check = described_class.call(pool, weather: weather)
    expect(check).to be_notified
    expect(TelegramBot.sender.deliveries.last).to include(to: "424242")
    expect(check.text_message.channel).to eq("telegram")
  end

  it "doesn't alert when Telegram is chosen but not linked" do
    pool = create(:pool, notification_channel: "telegram")
    expect(described_class.call(pool, weather: weather)).not_to be_notified
  end
end

RSpec.describe PoolCheck, "planning" do
  let(:pool) { create(:pool, assumed_setpoint: 91) }

  it "plans from the estimated water temperature" do
    pool.record_water_temp!(84)
    check = described_class.call(pool, weather: FakeWeather.new(forecast: flat_forecast(65)), notify: false)
    expect(check.recommendation.details["water_now"]).to be_within(0.5).of(84)
    expect(check.recommendation.reason).to include("heat it up from about 84°F")
  end

  it "says when cooler weather is coming" do
    snap = hourly_forecast { |h| (3 * 24...5 * 24).cover?(h) ? 40 : 65 }
    pool.update!(assumed_setpoint: nil)
    described_class.call(pool, weather: FakeWeather.new(forecast: snap))
    expect(Sms.sender.last_body).to start_with("Cooler weather coming.\nYour heater should be set to:")
  end
end

RSpec.describe PoolCheck, "cover advice" do
  let(:pool) { create(:pool, has_cover: true, cover_on: true, assumed_setpoint: 97) }

  before { pool.record_water_temp!(97) }

  it "tells you to take the cover off when the water needs to cool, and assumes you did" do
    described_class.call(pool, weather: FakeWeather.new(forecast: flat_forecast(65)))
    expect(Sms.sender.last_body).to include("Remove the cover for rapid cooling.")
    expect(pool.reload.cover_on).to be false
  end

  it "alerts for a cover change even when the heater setting stays the same" do
    target = described_class.call(pool, weather: FakeWeather.new(forecast: flat_forecast(65)), notify: false).recommendation.target_temp
    pool.update!(assumed_setpoint: target)
    expect { described_class.call(pool, weather: FakeWeather.new(forecast: flat_forecast(65))) }
      .to change { Sms.sender.deliveries.size }.by(1)
  end

  it "says nothing about a cover the pool doesn't have" do
    pool.update!(has_cover: false)
    described_class.call(pool, weather: FakeWeather.new(forecast: flat_forecast(65)))
    expect(Sms.sender.last_body).not_to include("cover")
  end
end

RSpec.describe PoolCheck, "pump advice" do
  let(:pool) do
    create(:pool, heat_rate_per_hour: 0.3, pump_on_1: "06:00", pump_off_1: "10:00", pump_on_2: "", pump_off_2: "",
                  assumed_setpoint: 90)
  end

  it "tells you to run the pump around the clock, and assumes you did" do
    pool.record_water_temp!(82)
    described_class.call(pool, weather: FakeWeather.new(forecast: flat_forecast(65)))
    expect(Sms.sender.last_body).to include("Leave the pump running 24 hours for now.")
    expect(pool.reload.pump_extended).to be true
  end

  # A pool whose normal pump hours keep up fine (2°F/h, 4-10am and 4-10pm), checked
  # at several times of day: running around the clock is no longer needed.
  (0..23).step(4).each do |hour|
    it "tells you to go back to the normal schedule when it's no longer needed (check at #{hour}:15)" do
      capable = create(:pool, heat_rate_per_hour: 2, pump_extended: true, assumed_setpoint: 91)
      zone = capable.zone
      travel_to(zone.local(2026, 10, 5, hour, 15)) do
        capable.record_water_temp!(91)
        described_class.call(capable, weather: FakeWeather.new(forecast: flat_forecast(65)))
        expect(Sms.sender.last_body).to include("Put the pump back on its normal schedule.")
        expect(capable.reload.pump_extended).to be false
      end
    end
  end

  it "keeps it running for a pool that can't keep up on its normal hours" do
    pool.update!(pump_extended: true, assumed_setpoint: 91)
    travel_to(pool.zone.local(2026, 10, 5, 13, 15)) do
      pool.record_water_temp!(91)
      described_class.call(pool, weather: FakeWeather.new(forecast: flat_forecast(65)))
      expect(pool.reload.pump_extended).to be true
    end
  end
end

RSpec.describe PoolCheck, ".message_for" do
  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }

  def message(pool, details)
    rows = (0...(5 * 24)).map { |h| { t: (zone.local(2026, 10, 5) + h.hours).iso8601, air: details.fetch(:air).call(h) } }
    result = Recommenders::Result.new(raw_target: 94, reason: "Because.", details: details.except(:air).merge(series: rows))
    described_class.message_for(pool, result)
  end

  let(:steady) { ->(_) { 65 } }

  it "is the heater setting and the request for a reading, nothing more, in steady weather without a cover" do
    pool = build(:pool, has_cover: false)
    expect(message(pool, air: steady, cover_on: nil, pump_extra: false))
      .to eq("Your heater should be set to: 94°F\nRespond with current pool temperature to improve system accuracy.")
  end

  it "leads with warmer or cooler weather when a coming day's average differs by more than 5°F" do
    pool = build(:pool, has_cover: false)
    expect(message(pool, air: ->(h) { h < 48 ? 60 : 70 }, pump_extra: false)).to start_with("Warmer weather coming.\n")
    expect(message(pool, air: ->(h) { h < 48 ? 60 : 50 }, pump_extra: false)).to start_with("Cooler weather coming.\n")
    expect(message(pool, air: ->(h) { h < 48 ? 60 : 64 }, pump_extra: false)).to start_with("Your heater")
  end

  it "says what to do with the cover, for pools with one" do
    pool = build(:pool, has_cover: true)
    expect(message(pool, air: steady, cover_on: true, pump_extra: false)).to include("\nCover should be on when not in use.\n")
    expect(message(pool, air: steady, cover_on: false, pump_extra: false)).to include("\nRemove the cover for rapid cooling.\n")
  end
end
