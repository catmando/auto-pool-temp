require "rails_helper"

RSpec.describe "Test mode" do
  let(:pool) { create(:pool, :telegram) }

  before { sign_in_as(pool.user) }

  it "saves the live forecast and the forecast behind the current plan" do
    expect { post forecast_snapshots_path, params: { source: "live" } }.to change(pool.forecast_snapshots, :count).by(1)
    get root_path # makes a plan
    expect { post forecast_snapshots_path, params: { source: "plan" } }.to change(pool.forecast_snapshots, :count).by(1)
    expect(flash[:notice]).to include("Saved test forecast")
  end

  it "reports a forecast failure when saving" do
    Weather.provider.error = Weather::OpenMeteo::Error.new("down")
    post forecast_snapshots_path, params: { source: "live" }
    expect(flash[:alert]).to include("down")
  end

  it "turns test mode on and off, with a banner while on" do
    snapshot = ForecastSnapshot.capture!(pool, name: "Frozen")
    patch test_mode_path, params: { snapshot_id: snapshot.id }
    expect(pool.reload.test_snapshot).to eq(snapshot)
    get root_path
    expect(response.body).to include("Test mode:", "Frozen", "No alerts are sent")
    expect(response.body).not_to include("Send alert now")

    patch test_mode_path, params: { snapshot_id: "" }
    expect(pool.reload).not_to be_test_mode
  end

  it "re-plans when test mode changes" do
    get root_path
    snapshot = ForecastSnapshot.capture!(pool, name: "Frozen")
    patch test_mode_path, params: { snapshot_id: snapshot.id }
    get root_path
    expect(pool.recommendations.recent.first.details["test_snapshot_id"]).to eq(snapshot.id)
  end

  it "lists and deletes saved forecasts on Settings, and shows them in the Lab" do
    snapshot = ForecastSnapshot.capture!(pool, name: "Frozen")
    get edit_pool_path
    expect(response.body).to include("Test mode", "Frozen")
    get lab_path
    expect(response.body).to include("Saved: Frozen")
    delete forecast_snapshot_path(snapshot)
    expect(pool.forecast_snapshots).to be_empty
  end

  it "can't touch another pool's forecasts" do
    other = ForecastSnapshot.capture!(create(:pool))
    patch test_mode_path, params: { snapshot_id: other.id }
    expect(response).to have_http_status(:not_found)
  end
end
