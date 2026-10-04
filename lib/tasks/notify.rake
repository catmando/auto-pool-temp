namespace :notify do
  desc "Point the Twilio and Telegram webhooks (whichever are configured) at BASE_URL"
  task :webhooks, [ :base_url ] => :environment do |_, args|
    base_url = (args[:base_url].presence || ENV["BASE_URL"].presence || abort("Usage: bin/rails 'notify:webhooks[https://your-public-host]'")).chomp("/")
    failed = false

    if Sms::TwilioSender.configured?
      begin
        puts "Twilio SMS webhook -> #{Sms::TwilioSetup.new.point_webhook_at!(base_url)}"
      rescue Sms::Error, Twilio::REST::TwilioError => e
        failed = true
        puts "Twilio webhook not set: #{e.message}"
      end
    else
      puts "Twilio not configured; skipping."
    end

    if TelegramBot.configured?
      begin
        url = "#{base_url}/telegram/webhook"
        TelegramBot::Client.new.set_webhook(url)
        puts "Telegram webhook -> #{url}"
      rescue TelegramBot::Error => e
        failed = true
        puts "Telegram webhook not set: #{e.message}"
      end
    else
      puts "Telegram not configured; skipping."
    end

    exit 1 if failed
  end
end

namespace :telegram do
  desc "Check the Telegram bot token and webhook"
  task status: :environment do
    abort "No Telegram bot token. Add telegram: bot_token: to bin/rails credentials:edit" unless TelegramBot.configured?

    client = TelegramBot::Client.new
    info = client.webhook_info
    puts "Bot: @#{client.username}"
    puts "Webhook: #{info['url'].presence || '(not set)'}#{" (pending: #{info['pending_update_count']})" if info['pending_update_count'].to_i.positive?}"
    puts "Last webhook error: #{info['last_error_message']}" if info["last_error_message"].present?
  rescue TelegramBot::Error => e
    abort e.message
  end
end
