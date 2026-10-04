# Where a pool's messages go. Each channel has a sender with the same
# interface (deliver(to:, body:) -> Sms::Delivery) and a pool attribute
# holding the confirmed address.
module Notifications
  CHANNELS = {
    "sms" => { label: "Text message (Twilio)", address: :phone_number },
    "telegram" => { label: "Telegram", address: :telegram_chat_id }
  }.freeze

  def self.channels = CHANNELS.keys

  def self.label(channel) = CHANNELS.fetch(channel.to_s)[:label]

  def self.sender(channel)
    case channel.to_s
    when "sms" then Sms.sender
    when "telegram" then TelegramBot.sender
    else raise ArgumentError, "unknown channel #{channel.inspect}"
    end
  end

  def self.address(pool, channel = pool.notification_channel)
    pool.public_send(CHANNELS.fetch(channel.to_s)[:address])
  end
end
