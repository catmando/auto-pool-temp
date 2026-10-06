class AddSmsConsentToPools < ActiveRecord::Migration[8.1]
  def change
    # When the owner checked "I agree to receive text alerts" (carrier opt-in record).
    add_column :pools, :sms_consent_at, :datetime
  end
end
