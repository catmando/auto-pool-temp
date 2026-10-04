# Log of every message sent or received, on any channel (SMS or Telegram).
class TextMessage < ApplicationRecord
  DIRECTIONS = %w[outbound inbound].freeze
  FAILED_STATUSES = %w[failed undelivered].freeze
  # SMS statuses that can still change (Twilio's final ones are delivered/undelivered/failed).
  PENDING_SMS_STATUSES = %w[sending queued accepted scheduled sent].freeze

  # Plain-English meanings for the Twilio error codes we're likely to hit.
  TWILIO_ERRORS = {
    30034 => "carrier blocked it: the Twilio number isn't A2P 10DLC registered yet",
    30032 => "carrier blocked it: the toll-free number isn't verified yet",
    30007 => "carrier filtered it as spam",
    30003 => "the phone is unreachable (off or out of service)",
    30005 => "unknown or inactive number",
    30006 => "the number can't receive texts (landline?)",
    21610 => "you've replied STOP to this number; text START to it to resume",
    21608 => "trial accounts can only text verified numbers"
  }.freeze

  # Seconds between delivery-status polls (zeroed in specs).
  class_attribute :delivery_poll_wait, default: 1.5

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

  def self.describe_twilio_error(code)
    return if code.blank?

    "Twilio error #{code}: #{TWILIO_ERRORS.fetch(code.to_i) { "see https://www.twilio.com/docs/api/errors/#{code}" }}"
  end

  def failed? = FAILED_STATUSES.include?(status)

  def delivery_pending? = channel == "sms" && direction == "outbound" && provider_sid.present? && PENDING_SMS_STATUSES.include?(status)

  # Asks Twilio what became of a pending SMS. Never raises.
  def refresh_delivery_status!(sender: Sms.sender)
    return self unless delivery_pending? && sender.respond_to?(:lookup)

    delivery, error_code = sender.lookup(provider_sid)
    update!(status: delivery.status, error: self.class.describe_twilio_error(error_code))
    self
  rescue Sms::Error => e
    Rails.logger.warn("Couldn't refresh SMS #{provider_sid}: #{e.message}")
    self
  end

  # Polls briefly for a final SMS status (used right after sending a code).
  def await_delivery_status!(tries: 4, wait: delivery_poll_wait, sender: Sms.sender)
    tries.times do
      break unless delivery_pending?

      sleep wait
      refresh_delivery_status!(sender: sender)
    end
    self
  end
end
