require "capybara/cuprite"

# js: true system specs run in headless Chrome. Set BROWSER_PATH if Chrome isn't
# in a standard place (this Mac has "Google Chrome Beta").
Capybara.register_driver(:chrome_headless) do |app|
  candidates = [ ENV["BROWSER_PATH"], "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                 "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome Beta" ]
  options = { window_size: [ 1200, 900 ], process_timeout: 20, timeout: 10 }
  path = candidates.compact.find { |p| File.executable?(p) }
  options[:browser_path] = path if path
  Capybara::Cuprite::Driver.new(app, **options)
end
