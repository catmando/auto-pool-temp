# Confirms the pool's phone number: text a 6-digit code, the user gives it back
# (on the Settings page or by replying to the text).
class PhoneVerification
  CODE_TTL = 10.minutes
  RESEND_WAIT = 30.seconds
  MAX_ATTEMPTS = 5

  Error = Class.new(StandardError)

  def initialize(pool, now: Time.current)
    @pool = pool
    @now = now
  end

  def send_code!(sender: nil)
    raise Error, "Enter a mobile number first." if @pool.phone_number.blank?
    if @pool.phone_verification_sent_at&.after?(@now - RESEND_WAIT)
      raise Error, "A code was just sent. Wait #{RESEND_WAIT.inspect} before asking for another."
    end

    code = format("%06d", SecureRandom.random_number(1_000_000))
    @pool.update!(phone_verification_digest: BCrypt::Password.create(code),
                  phone_verification_sent_at: @now, phone_verification_attempts: 0)
    message = TextMessage.deliver(pool: @pool, channel: "sms", sender: sender,
      body: "Auto Pool Temp code: #{code}. Enter it in Settings or reply with it. Expires in #{CODE_TTL.inspect}.")
    raise Error, "Couldn't send the code: #{message.error}" if message.failed?

    message
  end

  # Returns true and marks the phone verified when +code+ is right.
  def confirm(code)
    return false if pending_digest.nil? || expired? || @pool.phone_verification_attempts >= MAX_ATTEMPTS

    if BCrypt::Password.new(pending_digest).is_password?(code.to_s.gsub(/\D/, ""))
      @pool.update!(phone_verified_at: @now, phone_verification_digest: nil, phone_verification_attempts: 0)
      true
    else
      @pool.increment!(:phone_verification_attempts)
      false
    end
  end

  def pending? = pending_digest.present? && !expired?

  def failure_reason
    if pending_digest.nil? then "No code is waiting. Send a new one."
    elsif expired? then "That code expired. Send a new one."
    elsif @pool.phone_verification_attempts >= MAX_ATTEMPTS then "Too many tries. Send a new code."
    else "That code isn't right."
    end
  end

  private

  def pending_digest = @pool.phone_verification_digest

  def expired?
    @pool.phone_verification_sent_at.nil? || @pool.phone_verification_sent_at.before?(@now - CODE_TTL)
  end
end
