# Only accept requests Twilio signed with our auth token (X-Twilio-Signature).
module TwilioSignature
  extend ActiveSupport::Concern

  included do
    skip_forgery_protection
    before_action :verify_twilio_signature
  end

  private

  def verify_twilio_signature
    token = Sms.config(:auth_token)
    return head(:service_unavailable) if token.blank?

    validator = Twilio::Security::RequestValidator.new(token)
    head :forbidden unless validator.validate(request.original_url, request.POST, request.headers["X-Twilio-Signature"].to_s)
  end
end
