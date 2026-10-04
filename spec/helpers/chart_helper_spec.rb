require "rails_helper"

RSpec.describe ChartHelper do
  let(:zone) { ActiveSupport::TimeZone["UTC"] }
  let(:rows) do
    (0..47).map do |h|
      { "t" => (Time.utc(2026, 10, 1) + h.hours).iso8601, "smoothed_air" => 60, "desired" => 93,
        "pool" => 90 + h * 0.1, "setpoint" => h < 31 ? 92 : 95, "pump" => (4...10).cover?(h % 24) ? 1.0 : 0.0 }
    end
  end

  it "draws expected water, ideal, and air lines, but no heater-setting line" do
    html = helper.plan_chart(rows, zone: zone)
    expect(html).to include("<svg", 'class="line pool"', 'class="line desired"', 'class="line air"',
                            "Expected water", "Ideal pool", "Heater or cover changes")
    expect(html).not_to include('class="line setpoint"')
    expect(html.scan("<polyline").size).to eq(3)
  end

  it "marks each change with a dot on the expected-water line, without labels" do
    html = helper.plan_chart(rows, zone: zone)
    expect(html.scan(/class="setpoint-marker"/).size).to eq(2)
    expect(html).not_to include("setpoint-label")
  end

  it "shades the hours the pump runs" do
    html = helper.plan_chart(rows, zone: zone)
    expect(html.scan(/class="pump-band"/).size).to eq(12)
    expect(html).to include("Pump on")
  end

  it "labels days" do
    expect(helper.plan_chart(rows, zone: zone)).to include(">Fri<")
  end

  it "draws older recommendations without a plan" do
    html = helper.forecast_chart(create(:recommendation))
    expect(html).to include('class="line desired"')
    expect(html).not_to include("setpoint-marker")
  end

  it "handles missing data" do
    expect(helper.forecast_chart(create(:recommendation, details: {}))).to include("No forecast data")
  end
end
