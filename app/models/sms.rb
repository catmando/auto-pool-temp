# SMS delivery. Uses Twilio when credentials are present, otherwise just logs
# (so development and a not-yet-configured install work without sending texts).
#
# Twilio config comes from ENV or Rails credentials:
#   TWILIO_ACCOUNT_SID / twilio.account_sid
#   TWILIO_AUTH_TOKEN  / twilio.auth_token
#   TWILIO_FROM_NUMBER / twilio.from_number
module Sms
  Delivery = Data.define(:sid, :status)
  Error = Class.new(StandardError)

  mattr_writer :sender

  def self.sender
    @@sender ||= TwilioSender.configured? ? TwilioSender.new : LogSender.new
  end

  # Where Twilio reports delivery results; nil without a public URL (dev/test).
  def self.status_callback_url
    base = ENV["APP_URL"].presence || Rails.application.config.x.public_url.presence
    base && "#{base.chomp("/")}/twilio/status"
  end

  def self.config(key)
    ENV["TWILIO_#{key.to_s.upcase}"].presence || Rails.application.credentials.dig(:twilio, key)
  end
end
