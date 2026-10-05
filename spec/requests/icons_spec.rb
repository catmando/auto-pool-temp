require "rails_helper"

RSpec.describe "App icon" do
  it "links the SVG favicon, a PNG fallback, and the Apple touch icon" do
    create(:user) # otherwise sign-in redirects to sign-up
    get new_session_path
    expect(response.body).to include('rel="icon" href="/icon.svg" type="image/svg+xml"', 'rel="icon" href="/icon.png"',
                                     'rel="apple-touch-icon" href="/icon.png"')
  end

  it "is the pool-and-thermometer icon, not the Rails placeholder" do
    svg = Rails.public_path.join("icon.svg").read
    expect(svg).to include("<title>Auto Pool Temp</title>", "#0b7fab", "Thermometer")
  end

  it "has a 512x512 PNG with transparency" do
    png = Rails.public_path.join("icon.png").binread
    expect(png[0, 8]).to eq("\x89PNG\r\n\x1A\n".b)
    width, height = png[16, 8].unpack("NN")
    expect([ width, height ]).to eq([ 512, 512 ])
    expect(png[25].ord).to eq(6) # color type 6: RGBA
  end
end
