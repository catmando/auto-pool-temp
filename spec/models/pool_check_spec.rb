require "rails_helper"

RSpec.describe PoolCheck do
  let(:pool) { create(:pool, assumed_setpoint: 85, setpoint_source: "user_reported") }
  let(:weather) { FakeWeather.new(forecast: flat_forecast(65, time_zone: "America/Chicago")) }
  let(:sender) { FakeSmsSender.new }
  let(:now) { Time.current }

  def check(**options) = described_class.call(pool, weather: weather, sender: sender, now: now, **options)

  it "fetches the forecast for the pool's location" do
    check
    expect(weather.requests).to eq([ { latitude: pool.latitude, longitude: pool.longitude, days: 10 } ])
  end

  it "records a recommendation" do
    result = check
    expect(result.recommendation).to have_attributes(strategy: "lookahead", target_temp: 91, assumed_setpoint: 85)
    expect(result.recommendation.reason).to include("91°F")
    expect(result.recommendation.series).not_to be_empty
  end

  it "uses the pool's chosen strategy" do
    pool.update!(strategy: "linear")
    expect(check.recommendation.strategy).to eq("linear")
  end

  context "when the setting should change" do
    it "texts the user, stating the assumption" do
      check
      expect(sender.deliveries.size).to eq(1)
      body = sender.deliveries.first[:body]
      expect(body).to include("set the heater to 91°F", "assuming it's at 85°F", "reply with the actual setting")
    end

    it "assumes the user follows the advice" do
      result = check
      expect(result).to be_notified
      expect(pool.reload).to have_attributes(assumed_setpoint: 91, setpoint_source: "recommended")
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
    before { pool.update!(assumed_setpoint: 91) }

    it "doesn't text" do
      result = check
      expect(sender.deliveries).to be_empty
      expect(result).not_to be_notified
    end
  end

  context "when the current setting is unknown" do
    before { pool.update!(assumed_setpoint: nil) }

    it "texts and says so" do
      check
      expect(sender.deliveries.first[:body]).to include("don't know its current setting", "reply with it")
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
