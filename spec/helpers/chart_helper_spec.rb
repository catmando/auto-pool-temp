require "rails_helper"

RSpec.describe ChartHelper do
  it "draws an SVG with a line per series and a legend" do
    html = helper.forecast_chart(create(:recommendation))
    expect(html).to include("<svg", 'class="line air"', 'class="line desired"', 'class="line plan"', "Ideal pool")
    expect(html.scan("<polyline").size).to eq(4)
  end

  it "labels days" do
    html = helper.forecast_chart(create(:recommendation))
    expect(html).to include(">Thu<").or include(">Wed<")
  end

  it "omits series that aren't present" do
    rec = create(:recommendation, details: { "series" => [
      { "t" => "2026-10-01T00:00:00Z", "air" => 70, "smoothed_air" => 70, "desired" => 88 },
      { "t" => "2026-10-01T01:00:00Z", "air" => 72, "smoothed_air" => 70, "desired" => 88 }
    ] })
    expect(helper.forecast_chart(rec)).not_to include("line plan")
  end

  it "handles missing data" do
    expect(helper.forecast_chart(create(:recommendation, details: {}))).to include("No forecast data")
  end
end
