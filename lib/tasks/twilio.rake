namespace :twilio do
  desc "Check the Twilio configuration and show the number's webhook"
  task status: :environment do
    setup = Sms::TwilioSetup.new
    abort "Twilio is missing: #{setup.missing_settings.join(', ')}. Run: bin/rails credentials:edit" unless setup.configured?

    status = setup.status
    puts "Twilio configured. Number: #{status[:from_number]}"
    puts "Incoming SMS webhook: #{status[:sms_method]} #{status[:sms_url].presence || '(not set)'}"
  rescue Sms::Error, Twilio::REST::TwilioError => e
    abort "Twilio error: #{e.message}"
  end

  desc "Point the Twilio number's incoming SMS webhook at BASE_URL (e.g. https://abc.trycloudflare.com)"
  task :webhook, [ :base_url ] => :environment do |_, args|
    base_url = args[:base_url].presence || ENV["BASE_URL"].presence || abort("Usage: bin/rails 'twilio:webhook[https://your-public-host]'")
    puts "Incoming SMS webhook set to #{Sms::TwilioSetup.new.point_webhook_at!(base_url)}"
  rescue Sms::Error, Twilio::REST::TwilioError => e
    abort "Twilio error: #{e.message}"
  end

  desc "Send a test text to the pool's phone number (or TO=+1...)"
  task test_sms: :environment do
    abort "Twilio isn't configured. Run: bin/rails credentials:edit" unless Sms::TwilioSender.configured?

    pool = Pool.where.not(phone_number: nil).first || abort("Set a phone number in Settings first.")
    to = ENV["TO"].presence || pool.phone_number
    message = TextMessage.deliver(pool: pool, channel: "sms", to: to, body: "Auto Pool Temp test: Twilio is working. Reply STATUS to try a reply.")
    abort "Send failed: #{message.error}" if message.failed?
    puts "Sent to #{to} (#{message.provider_sid}, #{message.status})"
  end
end
