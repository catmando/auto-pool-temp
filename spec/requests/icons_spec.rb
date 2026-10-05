require "rails_helper"

# Phones need more than an SVG favicon: Android Chrome fetches /favicon.ico and
# sized PNGs, and uses the manifest for "Add to Home screen" (owner couldn't see
# the icon on Android, 2026-10-05).
RSpec.describe "App icons" do
  def png_size(name)
    png = Rails.public_path.join(name).binread
    expect(png[0, 8]).to eq("\x89PNG\r\n\x1A\n".b)
    png[16, 8].unpack("NN")
  end

  it "links favicon.ico, a sized PNG, the SVG, the Apple touch icon, the manifest, and a theme color" do
    create(:user) # otherwise sign-in redirects to sign-up
    get new_session_path
    expect(response.body).to include('rel="icon" href="/favicon.ico" sizes="48x48"',
                                     'rel="icon" href="/icon-192.png" type="image/png" sizes="192x192"',
                                     'rel="icon" href="/icon.svg" type="image/svg+xml"',
                                     'rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180"',
                                     'rel="manifest" href="/manifest.json"', 'name="theme-color" content="#0b7fab"')
  end

  it "has a real multi-size favicon.ico (16, 32, 48)" do
    ico = Rails.public_path.join("favicon.ico").binread
    reserved, type, count = ico[0, 6].unpack("vvv")
    expect([ reserved, type, count ]).to eq([ 0, 1, 3 ])
    sizes = (0...count).map { |i| ico[6 + i * 16, 2].unpack("CC") }
    expect(sizes).to eq([ [ 16, 16 ], [ 32, 32 ], [ 48, 48 ] ])
  end

  it "has PNGs at the sizes phones ask for" do
    expect(png_size("icon-192.png")).to eq([ 192, 192 ])
    expect(png_size("icon-512.png")).to eq([ 512, 512 ])
    expect(png_size("icon-maskable-192.png")).to eq([ 192, 192 ])
    expect(png_size("icon-maskable-512.png")).to eq([ 512, 512 ])
    expect(png_size("apple-touch-icon.png")).to eq([ 180, 180 ])
  end

  it "serves the manifest with the app's name and icons, including maskable ones for Android" do
    get "/manifest.json"
    expect(response).to have_http_status(:ok)
    manifest = response.parsed_body
    expect(manifest).to include("name" => "Auto Pool Temp", "short_name" => "Pool Temp", "theme_color" => "#0b7fab",
                                "display" => "standalone", "start_url" => "/")
    expect(manifest["icons"]).to include(include("src" => "/icon-192.png", "sizes" => "192x192"),
                                         include("src" => "/icon-maskable-512.png", "purpose" => "maskable"))
    manifest["icons"].each { |icon| expect(Rails.public_path.join(icon["src"].delete_prefix("/"))).to exist }
  end

  it "is the pool-and-thermometer icon, not the Rails placeholder" do
    expect(Rails.public_path.join("icon.svg").read).to include("<title>Auto Pool Temp</title>", "#0b7fab", "Thermometer")
  end
end
