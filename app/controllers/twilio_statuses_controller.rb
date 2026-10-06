# Twilio's delivery reports for texts we sent: queued -> sent -> delivered, or
# undelivered/failed with an error code (e.g. 30034, carrier registration). The
# message log then shows what really happened.
class TwilioStatusesController < ActionController::Base
  include TwilioSignature

  def create
    message = TextMessage.find_by(provider_sid: params[:MessageSid])
    if message
      message.update!(status: params[:MessageStatus].presence || message.status,
                      error: TextMessage.describe_twilio_error(params[:ErrorCode].presence))
    end
    head :no_content
  end
end
