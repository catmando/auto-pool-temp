require "rails_helper"

RSpec.describe SmsReply do
  let!(:pool) { create(:pool, assumed_setpoint: 91, setpoint_source: "recommended") }
  let(:sender) { FakeSmsSender.new }
  let(:weather) { FakeWeather.new(forecast: flat_forecast(65)) }

  def reply(body, from: "(512) 555-0100")
    described_class.handle(from: from, body: body, sender: sender, weather: weather)
  end

  def last_reply = sender.deliveries.last[:body]

  it "logs the inbound message" do
    reply("status")
    inbound = TextMessage.find_by(direction: "inbound")
    expect(inbound).to have_attributes(pool: pool, body: "status", from: "(512) 555-0100")
  end

  it "ignores unknown senders (but logs them)" do
    expect(reply("85", from: "+19995550000")).to eq(:unknown_sender)
    expect(sender.deliveries).to be_empty
    expect(TextMessage.where(direction: "inbound", pool: nil).count).to eq(1)
  end

  describe "reporting the actual setting" do
    %w[88 88F 88°F set\ 88 Set\ to\ 88].each do |body|
      it "understands #{body.inspect}" do
        reply(body)
        expect(last_reply).to start_with("Thanks, noted 88°F")
      end
    end

    it "asks for a change when the reported setting is off" do
      reply("85")
      expect(last_reply).to include("noted 85°F", "change it to 91°F")
      expect(pool.reload).to have_attributes(assumed_setpoint: 91, setpoint_source: "recommended")
    end

    it "confirms when the reported setting is right" do
      reply("91")
      expect(last_reply).to include("That's right for now")
      expect(pool.reload).to have_attributes(assumed_setpoint: 91, setpoint_source: "user_reported")
    end

    it "rejects implausible settings" do
      reply("300")
      expect(last_reply).to include("doesn't look like a heater setting")
      expect(pool.reload.assumed_setpoint).to eq(91)
    end

    it "reports forecast failures politely" do
      weather.error = Weather::OpenMeteo::Error.new("down")
      reply("85")
      expect(last_reply).to include("couldn't check the forecast")
    end
  end

  it "answers STATUS" do
    reply("Status")
    expect(last_reply).to include("Target now: 91°F", "set to 91°F")
  end

  it "pauses and resumes alerts" do
    reply("PAUSE")
    expect(pool.reload.notifications_enabled).to be false
    expect(last_reply).to include("paused")
    reply("resume")
    expect(pool.reload.notifications_enabled).to be true
  end

  it "sends help for anything else" do
    reply("what?")
    expect(last_reply).to eq(described_class::HELP)
  end
end
