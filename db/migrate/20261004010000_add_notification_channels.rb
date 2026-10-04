class AddNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    change_table :pools, bulk: true do |t|
      t.string :notification_channel, null: false, default: "sms"

      # SMS: a texted code the user gives back
      t.datetime :phone_verified_at
      t.string :phone_verification_digest
      t.datetime :phone_verification_sent_at
      t.integer :phone_verification_attempts, null: false, default: 0

      # Telegram: a one-time deep link token the bot receives back
      t.string :telegram_chat_id
      t.datetime :telegram_linked_at
      t.string :telegram_link_token
      t.datetime :telegram_link_sent_at
    end
    add_index :pools, :telegram_chat_id
    add_index :pools, :telegram_link_token, unique: true

    add_column :text_messages, :channel, :string, null: false, default: "sms"
  end
end
