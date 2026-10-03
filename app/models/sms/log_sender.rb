module Sms
  class LogSender
    def deliver(to:, body:)
      Rails.logger.info("[SMS not sent: Twilio not configured] to=#{to} body=#{body.inspect}")
      Delivery.new(sid: nil, status: "logged")
    end
  end
end
