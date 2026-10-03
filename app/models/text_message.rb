class TextMessage < ApplicationRecord
  DIRECTIONS = %w[outbound inbound].freeze

  belongs_to :pool, optional: true

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :body, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Sends a text and records it. Never raises: failures are stored on the record.
  def self.deliver(pool:, body:, to: pool.phone_number, sender: Sms.sender)
    message = create!(pool: pool, direction: "outbound", to: to, body: body, status: "sending")
    delivery = sender.deliver(to: to, body: body)
    message.update!(provider_sid: delivery.sid, status: delivery.status)
    message
  rescue Sms::Error => e
    message.update!(status: "failed", error: e.message)
    message
  end

  def failed? = status == "failed"
end
