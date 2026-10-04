require "rails_helper"

RSpec.describe "Dashboard" do
  let(:pool) { create(:pool, :telegram, assumed_setpoint: 88, setpoint_source: "recommended") }

  before { sign_in_as(pool.user) }

  it "sends an unlocated pool to settings" do
    pool.update!(latitude: nil, longitude: nil)
    get root_path
    expect(response).to redirect_to(edit_pool_path)
  end

  it "shows the setting, water estimate, plan, and schedule" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("88°F", "assumed: you followed the last alert", "~88°F", "assumed to match the heater",
                                     "Updated", "Austin, Texas, US", "alerts go to Telegram", "Send alert now if needed")
    expect(response.body).not_to include("Preview now")
  end

  describe "keeping the plan current (without sending anything)" do
    it "makes a plan on first visit" do
      expect { get root_path }.to change(pool.recommendations, :count).by(1)
      expect(TelegramBot.sender.deliveries).to be_empty
    end

    it "reuses a fresh plan" do
      get root_path
      expect { get root_path }.not_to change(pool.recommendations, :count)
    end

    it "re-plans when settings change" do
      get root_path
      travel 1.minute do
        patch pool_path, params: { pool: { heat_rate_per_hour: 1.5 } }
        expect { get root_path }.to change(pool.recommendations, :count).by(1)
      end
    end

    it "re-plans when a water reading comes in" do
      get root_path
      travel 1.minute do
        patch water_temp_path, params: { water_temp: "85" }
        expect { get root_path }.to change(pool.recommendations, :count).by(1)
      end
    end

    it "re-plans when the plan was made before the app started (e.g. a deploy changed the planner)" do
      get root_path
      allow(Rails.application.config).to receive(:booted_at).and_return(1.second.from_now)
      travel 2.seconds do
        expect { get root_path }.to change(pool.recommendations, :count).by(1)
      end
    end

    it "re-plans when the plan is over an hour old" do
      get root_path
      travel 61.minutes do
        expect { get root_path }.to change(pool.recommendations, :count).by(1)
      end
    end

    it "keeps showing the last plan if the forecast can't be fetched" do
      get root_path
      Weather.provider.error = Weather::OpenMeteo::Error.new("down")
      travel 2.hours do
        get root_path
        expect(response.body).to include("update the plan: down", "Set heater to")
      end
    end
  end

  it "warns when Telegram isn't connected" do
    pool.update!(telegram_chat_id: nil)
    get root_path
    expect(response.body).to include("not connected yet")
  end

  it "shows the plan chart and a table of upcoming settings" do
    get root_path
    expect(response.body).to include("setpoint-marker", "Set heater to", "Water then")
  end

  it "shows recent messages" do
    create(:text_message, pool: pool, body: "Set the heater to 93°F.")
    get root_path
    expect(response.body).to include("Set the heater to 93°F.")
  end
end
