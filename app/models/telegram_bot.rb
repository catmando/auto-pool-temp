require "net/http"

# Telegram Bot API delivery. Uses the real bot when a token is configured,
# otherwise logs (like Sms). Config from ENV or Rails credentials:
#   TELEGRAM_BOT_TOKEN / telegram.bot_token   (from @BotFather)
module TelegramBot
  API = "https://api.telegram.org".freeze
  Error = Class.new(StandardError)

  mattr_writer :sender

  def self.sender
    @@sender ||= configured? ? Client.new : Sms::LogSender.new
  end

  def self.token
    ENV["TELEGRAM_BOT_TOKEN"].presence || Rails.application.credentials.dig(:telegram, :bot_token)
  end

  def self.configured? = token.present?

  # Shared secret Telegram echoes in X-Telegram-Bot-Api-Secret-Token, derived
  # from the bot token so there's nothing extra to configure.
  def self.webhook_secret
    token && OpenSSL::HMAC.hexdigest("SHA256", token, "auto-pool-temp-webhook")[0, 48]
  end

  class Client
    def initialize(token: TelegramBot.token)
      @token = token
    end

    def deliver(to:, body:)
      result = call("sendMessage", chat_id: to, text: body, disable_web_page_preview: true)
      Sms::Delivery.new(sid: result["message_id"].to_s, status: "sent")
    rescue Error => e
      raise Sms::Error, e.message
    end

    def username
      @username ||= call("getMe").fetch("username")
    end

    def set_webhook(url, secret: TelegramBot.webhook_secret)
      call("setWebhook", url: url, secret_token: secret, allowed_updates: [ "message" ])
    end

    def webhook_info = call("getWebhookInfo")

    private

    def call(method, params = {})
      raise Error, "Telegram bot token not configured" if @token.blank?

      uri = URI("#{API}/bot#{@token}/#{method}")
      response = Net::HTTP.post(uri, params.to_json, "Content-Type" => "application/json")
      json = JSON.parse(response.body)
      raise Error, "Telegram #{method} failed: #{json['description'] || response.code}" unless json["ok"]

      json["result"]
    rescue JSON::ParserError, SocketError, Timeout::Error, SystemCallError => e
      raise Error, "Telegram #{method} failed: #{e.message}"
    end
  end
end
