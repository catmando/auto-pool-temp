require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "webmock/rspec"
require "capybara/rspec"

Rails.root.glob("spec/support/**/*.rb").sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

WebMock.disable_net_connect!(allow_localhost: true)

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ForecastHelpers
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :system

  config.before(:each, type: :system) { driven_by :rack_test }

  # Never hit real services from specs: swap in fakes app-wide.
  config.around do |example|
    original_weather = Weather.provider
    Weather.provider = FakeWeather.new
    Sms.sender = FakeSmsSender.new
    TelegramBot.sender = FakeSmsSender.new
    example.run
  ensure
    Weather.provider = original_weather
    Sms.sender = nil
    TelegramBot.sender = nil
  end
end
