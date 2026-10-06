module Sms
  class TwilioSender
    def self.configured?
      %i[account_sid auth_token from_number].all? { |k| Sms.config(k).present? }
    end

    def initialize(client: nil)
      @client = client
    end

    # Twilio reports each message's final status (delivered, or rejected by the carrier) to
    # TwilioStatusesController when the app has a public URL (production).
    def deliver(to:, body:)
      params = { from: Sms.config(:from_number), to: to, body: body }
      params[:status_callback] = Sms.status_callback_url if Sms.status_callback_url
      message = client.messages.create(**params)
      Delivery.new(sid: message.sid, status: message.status)
    rescue Twilio::REST::TwilioError => e
      raise Error, e.message
    end

    # Twilio accepts a message as "queued"; carriers can still reject it later.
    # Returns [current Delivery, Twilio error code or nil].
    def lookup(sid)
      message = client.messages(sid).fetch
      [ Delivery.new(sid: sid, status: message.status), message.error_code ]
    rescue Twilio::REST::TwilioError => e
      raise Error, e.message
    end

    private

    def client
      @client ||= Twilio::REST::Client.new(Sms.config(:account_sid), Sms.config(:auth_token))
    end
  end
end
