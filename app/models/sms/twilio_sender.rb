module Sms
  class TwilioSender
    def self.configured?
      %i[account_sid auth_token from_number].all? { |k| Sms.config(k).present? }
    end

    def initialize(client: nil)
      @client = client
    end

    def deliver(to:, body:)
      message = client.messages.create(from: Sms.config(:from_number), to: to, body: body)
      Delivery.new(sid: message.sid, status: message.status)
    rescue Twilio::REST::TwilioError => e
      raise Error, e.message
    end

    private

    def client
      @client ||= Twilio::REST::Client.new(Sms.config(:account_sid), Sms.config(:auth_token))
    end
  end
end
