require "rails_helper"

RSpec.describe Pool, "text alert consent" do
  let(:pool) { create(:pool, :telegram, sms_consent_at: nil) }

  it "won't send texts without a phone number and recorded consent" do
    pool.notification_channel = "sms"
    pool.phone_number = ""
    expect(pool).not_to be_valid
    expect(pool.errors.full_messages).to include("Phone number is needed for text alerts",
                                                 "Check the box agreeing to receive text alerts")
  end

  it "records when the box is checked, and keeps the original time on later saves" do
    travel_to Time.zone.local(2026, 10, 5, 9) do
      pool.update!(notification_channel: "sms", sms_consent: true)
    end
    expect(pool.reload.sms_consent_at).to eq(Time.zone.local(2026, 10, 5, 9))
    pool.update!(sms_consent: true, name: "Backyard")
    expect(pool.reload.sms_consent_at).to eq(Time.zone.local(2026, 10, 5, 9))
  end

  it "withdraws consent when the box is unchecked, which blocks text alerts" do
    pool.update!(sms_consent: true)
    expect(pool.update(notification_channel: "sms", sms_consent: false)).to be(false)
    expect(pool.update(notification_channel: "telegram", sms_consent: false)).to be(true)
    expect(pool.reload.sms_consent_at).to be_nil
  end

  it "won't text a confirmed number that has no recorded consent" do
    pool.update_columns(notification_channel: "sms", phone_number: "+15125550100", phone_verified_at: Time.current)
    expect(pool).not_to be_notifiable
    pool.update!(sms_consent: true)
    expect(pool).to be_notifiable
  end

  it "still saves routine changes on an older text pool without consent" do
    pool.update_columns(notification_channel: "sms", phone_number: "+15125550100")
    expect(pool.update(last_checked_at: Time.current)).to be(true)
  end

  it "doesn't need consent for Telegram" do
    expect(pool).to be_valid
  end
end
