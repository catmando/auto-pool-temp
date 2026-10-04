require "rails_helper"

RSpec.describe PhoneVerification do
  let(:pool) { create(:pool, :unverified) }
  let(:sender) { FakeSmsSender.new }
  let(:now) { Time.current }

  def verification(at = now) = described_class.new(pool, now: at)

  def send_code(at = now)
    verification(at).send_code!(sender: sender)
    sender.last_body[/\d{6}/]
  end

  describe "#send_code!" do
    it "texts a 6-digit code to the pool's phone, even if alerts use Telegram" do
      pool.update!(notification_channel: "telegram")
      code = send_code
      expect(code).to match(/\A\d{6}\z/)
      expect(sender.deliveries.last[:to]).to eq(pool.phone_number)
      expect(TextMessage.last.channel).to eq("sms")
    end

    it "stores only a digest of the code" do
      code = send_code
      expect(pool.reload.phone_verification_digest).to be_present
      expect(pool.phone_verification_digest).not_to include(code)
    end

    it "needs a phone number" do
      pool.update!(phone_number: nil)
      expect { send_code }.to raise_error(described_class::Error, /mobile number/)
    end

    it "limits how often codes are sent" do
      send_code
      expect { send_code(now + 10.seconds) }.to raise_error(described_class::Error, /just sent/)
      expect { send_code(now + 31.seconds) }.not_to raise_error
    end

    it "reports delivery failures" do
      sender.fail_with = "carrier blocked"
      expect { send_code }.to raise_error(described_class::Error, /carrier blocked/)
    end
  end

  describe "#confirm" do
    it "confirms the phone with the right code" do
      code = send_code
      expect(verification.confirm(code)).to be true
      expect(pool.reload).to be_phone_verified
      expect(pool.phone_verification_digest).to be_nil
    end

    it "ignores spaces and dashes" do
      code = send_code
      expect(verification.confirm("#{code[0, 3]} - #{code[3, 3]}")).to be true
    end

    it "rejects a wrong code and counts the attempt" do
      send_code
      expect(verification.confirm("000000x")).to be false
      expect(pool.reload.phone_verification_attempts).to eq(1)
      expect(verification.failure_reason).to eq("That code isn't right.")
    end

    it "locks out after too many attempts" do
      code = send_code
      5.times { verification.confirm("999999") unless code == "999999" }
      expect(verification.confirm(code)).to be false
      expect(verification.failure_reason).to include("Too many tries")
    end

    it "expires codes" do
      code = send_code
      later = verification(now + 11.minutes)
      expect(later.confirm(code)).to be false
      expect(later.failure_reason).to include("expired")
    end

    it "needs a code to have been sent" do
      expect(verification.confirm("123456")).to be false
      expect(verification.failure_reason).to include("No code")
    end
  end

  it "is reset when the phone number changes" do
    code = send_code
    verification.confirm(code)
    pool.update!(phone_number: "585-278-0000")
    expect(pool.reload).not_to be_phone_verified
  end
end
