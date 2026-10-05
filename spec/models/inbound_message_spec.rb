require "rails_helper"

RSpec.describe InboundMessage do
  let!(:pool) { create(:pool, assumed_setpoint: 91, setpoint_source: "recommended") }
  let(:sender) { FakeSmsSender.new }
  let(:weather) { FakeWeather.new(forecast: flat_forecast(65)) }

  def reply(body, from: "(512) 555-0100", channel: "sms")
    described_class.handle(channel: channel, from: from, body: body, sender: sender, weather: weather)
  end

  def last_reply = sender.last_body

  it "logs the inbound message" do
    reply("status")
    inbound = TextMessage.find_by(direction: "inbound")
    expect(inbound).to have_attributes(pool: pool, channel: "sms", body: "status", from: "(512) 555-0100")
  end

  it "replies on the same channel, to the sender" do
    reply("status")
    expect(sender.deliveries.last[:to]).to eq("(512) 555-0100")
    expect(TextMessage.where(direction: "outbound").last).to have_attributes(channel: "sms", pool: pool)
  end

  it "ignores unknown senders (but logs them)" do
    expect(reply("85", from: "+19995550000")).to eq(:unknown_sender)
    expect(sender.deliveries).to be_empty
    expect(TextMessage.where(direction: "inbound", pool: nil).count).to eq(1)
  end

  describe "reporting the actual setting" do
    [ "heater 88", "Heater 88F", "heater is 88", "set 88", "Set to 88" ].each do |body|
      it "understands #{body.inspect}" do
        reply(body)
        expect(last_reply).to start_with("Thanks, noted 88°F")
      end
    end

    it "asks for a change when the reported setting is off" do
      reply("heater 85")
      expect(last_reply).to include("noted 85°F").and match(/change it to 9[12]°F/) # 92 covers pump-off dips
      expect(pool.reload).to have_attributes(assumed_setpoint: last_reply[/change it to (\d+)/, 1].to_i, setpoint_source: "recommended")
    end

    it "confirms when the reported setting is right" do
      reply("heater 91")
      expect(last_reply).to include("That's right for now")
      expect(pool.reload).to have_attributes(assumed_setpoint: 91, setpoint_source: "user_reported")
    end

    it "rejects implausible settings" do
      reply("heater 300")
      expect(last_reply).to include("doesn't look like a heater setting")
      expect(pool.reload.assumed_setpoint).to eq(91)
    end

    it "reports forecast failures politely" do
      weather.error = Weather::OpenMeteo::Error.new("down")
      reply("heater 85")
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

  describe "SMS from a number that isn't confirmed yet" do
    let!(:pool) { create(:pool, :unverified) }

    before { PhoneVerification.new(pool).send_code!(sender: sender) }

    let(:code) { sender.deliveries.first[:body][/\d{6}/] }

    it "confirms the number when the reply is the code" do
      reply(code)
      expect(pool.reload).to be_phone_verified
      expect(last_reply).to include("this number is confirmed")
    end

    it "refuses other commands until confirmed" do
      reply("status")
      expect(pool.reload).not_to be_phone_verified
      expect(last_reply).to include("isn't right", "Confirm this number")
    end
  end

  describe "Telegram" do
    let!(:pool) { create(:pool, :telegram) }

    it "finds the pool by chat id" do
      reply("status", channel: "telegram", from: "424242")
      expect(last_reply).to include("Target now")
      expect(TextMessage.last).to have_attributes(channel: "telegram", to: "424242")
    end

    it "accepts slash commands" do
      reply("/pause", channel: "telegram", from: "424242")
      expect(pool.reload.notifications_enabled).to be false
    end

    describe "/start <token>" do
      let!(:other) { create(:pool) }

      it "links the chat to the pool that made the link" do
        token = TelegramLink.start!(other)
        reply("/start #{token}", channel: "telegram", from: "777")
        expect(other.reload).to have_attributes(telegram_chat_id: "777", telegram_link_token: nil)
        expect(last_reply).to start_with("Connected!")
        expect(sender.deliveries.last[:to]).to eq("777")
      end

      it "explains an expired or unknown link" do
        expect(reply("/start nope", channel: "telegram", from: "777")).to eq(:unknown_link)
        expect(last_reply).to include("expired or was already used")
      end

      it "handles a bare /start" do
        expect(reply("/start", channel: "telegram", from: "777")).to eq(:unknown_link)
      end
    end
  end
end

RSpec.describe InboundMessage, "water reports" do
  let!(:pool) { create(:pool, :telegram, assumed_setpoint: 91) }
  let(:sender) { FakeSmsSender.new }

  def reply(body) = described_class.handle(channel: "telegram", from: "424242", body: body, sender: sender,
                                           weather: FakeWeather.new(forecast: flat_forecast(65)))

  %w[water\ 86 w86 Water\ is\ 86.5F pool:\ 86].each do |body|
    it "understands #{body.inspect}" do
      reply(body)
      expect(pool.pool_logs.last).to have_attributes(kind: "water_reading", source: "telegram")
      expect(pool.pool_logs.last.water_temp.to_f).to be_between(86, 86.5)
      expect(sender.last_body).to start_with("Thanks, logged the water at 86")
    end
  end

  it "logs the reading with what the model expected, without changing the plan" do
    pool.update!(assumed_setpoint: 84)
    expect { reply("water 80") }.to change(pool.pool_logs, :count).by(1)
    log = pool.pool_logs.last
    expect(log).to have_attributes(kind: "water_reading", water_temp: 80, source: "telegram", expected_water_temp: 84)
    expect(sender.last_body).to eq("Thanks, logged the water at 80°F (I expected about 84°F).")
    expect(pool.reload.water_temp_source).to be_nil # the model isn't adjusted yet
  end

  it "rejects implausible readings" do
    reply("water 200")
    expect(sender.last_body).to include("doesn't look like a water temperature")
  end
end

RSpec.describe InboundMessage, "cover replies" do
  let!(:pool) { create(:pool, :telegram, has_cover: true, cover_on: true, assumed_setpoint: 90) }
  let(:sender) { FakeSmsSender.new }

  def reply(body) = described_class.handle(channel: "telegram", from: "424242", body: body, sender: sender)

  it "records the cover going off and on" do
    reply("cover off")
    expect(pool.reload.cover_on).to be false
    expect(sender.last_body).to eq("Got it, the cover is off.")
    reply("Cover On")
    expect(pool.reload.cover_on).to be true
  end
end

RSpec.describe InboundMessage, "pump replies" do
  let!(:pool) { create(:pool, :telegram, assumed_setpoint: 90) }
  let(:sender) { FakeSmsSender.new }

  def reply(body) = described_class.handle(channel: "telegram", from: "424242", body: body, sender: sender)

  it "records the pump running around the clock and back to normal" do
    reply("pump on")
    expect(pool.reload.pump_extended).to be true
    reply("Pump normal")
    expect(pool.reload.pump_extended).to be false
    expect(sender.last_body).to include("back on its normal schedule")
  end
end

RSpec.describe InboundMessage, "confirming an alert" do
  let!(:pool) { create(:pool, :telegram, assumed_setpoint: 94) }
  let(:sender) { FakeSmsSender.new }

  def reply(body, at: Time.current) = described_class.handle(channel: "telegram", from: "424242", body: body, sender: sender, now: at)

  %w[done DONE Done! ok yes 👍].each do |word|
    it "logs #{word.inspect} as the heater being set, now" do
      freeze_time do
        reply(word)
        expect(pool.pool_logs.last).to have_attributes(kind: "setting_confirmed", setpoint: 94, water_temp: nil, logged_at: Time.current)
        expect(pool.reload.setpoint_updated_at).to eq(Time.current) # assume the change happened when confirmed
        expect(sender.last_body).to eq("Thanks, logged the heater at 94°F.")
      end
    end
  end

  [ "done 86", "done, 86", "Done water 86", "ok 86F" ].each do |body|
    it "logs a water reading along with #{body.inspect}" do
      reply(body)
      expect(pool.pool_logs.last).to have_attributes(kind: "setting_confirmed", setpoint: 94, water_temp: 86)
      expect(sender.last_body).to start_with("Thanks, logged the heater at 94°F and the water at 86°F")
    end
  end

  it "treats a bare number as done, with the water at that temperature" do
    reply("86")
    expect(pool.pool_logs.last).to have_attributes(kind: "setting_confirmed", setpoint: 94, water_temp: 86)
    expect(sender.last_body).to start_with("Thanks, logged the heater at 94°F and the water at 86°F")
  end

  it "takes HEATER 84 as the heater's actual setting, not a confirmation" do
    reply("heater 90")
    expect(pool.reload.assumed_setpoint).not_to be_nil
    expect(pool.pool_logs.where(kind: "setting_confirmed")).to be_empty
  end
end
