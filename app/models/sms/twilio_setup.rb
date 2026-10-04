module Sms
  # Admin helpers for the Twilio account: check the config, point the phone
  # number's incoming-SMS webhook at this app, and send a test text.
  # Used by the twilio:* rake tasks and bin/tunnel.
  class TwilioSetup
    WEBHOOK_PATH = "/twilio/sms".freeze

    def initialize(client: nil)
      @client = client
    end

    def missing_settings
      %i[account_sid auth_token from_number].select { |k| Sms.config(k).blank? }
    end

    def configured? = missing_settings.empty?

    def phone_number
      @phone_number ||= client.incoming_phone_numbers.list(phone_number: Sms.config(:from_number)).first ||
        raise(Error, "#{Sms.config(:from_number)} isn't a phone number on this Twilio account")
    end

    def status
      number = phone_number
      { from_number: number.phone_number, sms_url: number.sms_url, sms_method: number.sms_method }
    end

    # +base_url+ is the app's public URL, e.g. https://abc.trycloudflare.com
    def point_webhook_at!(base_url)
      url = URI.join(base_url.to_s.sub(%r{/*\z}, "/"), WEBHOOK_PATH.delete_prefix("/")).to_s
      client.incoming_phone_numbers(phone_number.sid).update(sms_url: url, sms_method: "POST")
      url
    end

    private

    def client
      raise Error, "Twilio is missing: #{missing_settings.join(', ')}" unless configured?

      @client ||= Twilio::REST::Client.new(Sms.config(:account_sid), Sms.config(:auth_token))
    rescue Twilio::REST::TwilioError => e
      raise Error, e.message
    end
  end
end
