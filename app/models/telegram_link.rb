# Connects a pool to a Telegram chat. The app shows a t.me deep link carrying a
# one-time token; tapping it makes Telegram send "/start <token>" to the bot,
# which proves the person holding that Telegram account asked for it.
class TelegramLink
  TOKEN_TTL = 30.minutes

  def self.start!(pool, now: Time.current)
    token = SecureRandom.urlsafe_base64(18).tr("=", "")
    pool.update!(telegram_link_token: token, telegram_link_sent_at: now)
    token
  end

  def self.url(token, username:)
    "https://t.me/#{username}?start=#{token}"
  end

  # Called when the bot receives "/start <token>" from +chat_id+.
  # Returns the linked pool, or nil if the token is unknown or expired.
  def self.complete(token, chat_id:, now: Time.current)
    pool = Pool.find_by(telegram_link_token: token.to_s) if token.present?
    return nil if pool.nil? || pool.telegram_link_sent_at.nil? || pool.telegram_link_sent_at.before?(now - TOKEN_TTL)

    pool.update!(telegram_chat_id: chat_id.to_s, telegram_linked_at: now,
                 telegram_link_token: nil, telegram_link_sent_at: nil)
    pool
  end
end
