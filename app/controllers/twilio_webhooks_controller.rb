# Inbound SMS from Twilio. Replies are sent through the REST API (and logged),
# so the TwiML response is always empty.
class TwilioWebhooksController < ActionController::Base
  include TwilioSignature

  def create
    InboundMessage.handle(channel: "sms", from: params[:From], body: params[:Body])
    render xml: "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
  end
end
