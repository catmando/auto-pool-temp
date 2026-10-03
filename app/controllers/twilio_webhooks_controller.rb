# Inbound SMS from Twilio. Replies are sent through the REST API (and logged),
# so the TwiML response is always empty.
class TwilioWebhooksController < ActionController::Base
  skip_forgery_protection
  before_action :verify_twilio_signature

  def create
    SmsReply.handle(from: params[:From], body: params[:Body])
    render xml: "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
  end

  private

  def verify_twilio_signature
    token = Sms.config(:auth_token)
    if token.blank?
      head :service_unavailable
      return
    end

    validator = Twilio::Security::RequestValidator.new(token)
    signature = request.headers["X-Twilio-Signature"].to_s
    head :forbidden unless validator.validate(request.original_url, request.POST, signature)
  end
end
