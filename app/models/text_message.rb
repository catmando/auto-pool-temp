# Log of every message sent or received, on any channel (SMS or Telegram).
class TextMessage < ApplicationRecord
  DIRECTIONS = %w[outbound inbound].freeze

  belongs_to :pool, optional: true

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :channel, inclusion: { in: Notifications.channels }
  validates :body, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Sends a message and records it. Never raises: failures are stored on the record.
  # Defaults to the pool's chosen channel and confirmed address.
  def self.deliver(pool:, body:, channel: pool.notification_channel, to: nil, sender: nil)
    to ||= Notifications.address(pool, channel)
    message = create!(pool: pool, direction: "outbound", channel: channel, to: to, body: body, status: "sending")
    raise Sms::Error, "no #{Notifications.label(channel)} address" if to.blank?

    delivery = (sender || Notifications.sender(channel)).deliver(to: to, body: body)
    message.update!(provider_sid: delivery.sid, status: delivery.status)
    message
  rescue Sms::Error => e
    message.update!(status: "failed", error: e.message)
    message
  end

  def failed? = status == "failed"
end
