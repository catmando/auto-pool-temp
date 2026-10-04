require "rails_helper"

RSpec.describe ChartHelper do
  let(:rows) do
    (0..47).map do |h|
      { "t" => (Time.utc(2026, 10, 1) + h.hours).iso8601, "smoothed_air" => 60, "desired" => 93,
        "pool" => 90 + h * 0.1, "setpoint" => h < 24 ? 92 : 95 }
    end
  end

  it "draws the heater setting, expected water, ideal, and air" do
    html = helper.plan_chart(rows, zone: ActiveSupport::TimeZone["UTC"])
    expect(html).to include("<svg", 'class="line setpoint"', 'class="line pool"', 'class="line desired"', 'class="line air"',
                            "Heater setting", "Expected water", "Ideal pool")
    expect(html.scan("<polyline").size).to eq(4)
  end

  it "labels each setting change with its number" do
    html = helper.plan_chart(rows, zone: ActiveSupport::TimeZone["UTC"])
    expect(html.scan(/class="setpoint-label"[^>]*>(\d+)</).flatten).to eq(%w[92 95])
  end

  it "labels days" do
    expect(helper.plan_chart(rows, zone: ActiveSupport::TimeZone["UTC"])).to include(">Fri<")
  end

  it "draws older recommendations without a plan" do
    html = helper.forecast_chart(create(:recommendation))
    expect(html).to include('class="line desired"')
    expect(html).not_to include('class="line setpoint"')
  end

  it "handles missing data" do
    expect(helper.forecast_chart(create(:recommendation, details: {}))).to include("No forecast data")
  end
end
