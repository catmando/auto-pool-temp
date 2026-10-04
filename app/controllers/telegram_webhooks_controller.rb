# Updates from the Telegram bot. Telegram sends the secret we registered in
# X-Telegram-Bot-Api-Secret-Token; anything without it is rejected.
class TelegramWebhooksController < ActionController::Base
  skip_forgery_protection
  before_action :verify_secret

  def create
    message = params.dig(:message) || {}
    chat = message[:chat] || {}
    if chat[:type] == "private" && message[:text].present?
      InboundMessage.handle(channel: "telegram", from: chat[:id].to_s, body: message[:text])
    end
    head :ok
  end

  private

  def verify_secret
    expected = TelegramBot.webhook_secret
    if expected.blank?
      head :service_unavailable
    elsif !ActiveSupport::SecurityUtils.secure_compare(request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s, expected)
      head :forbidden
    end
  end
end
