class TelegramLinksController < ApplicationController
  # Make a fresh one-time link; the Settings page shows it.
  def create
    return redirect_to(edit_pool_path, alert: "The Telegram bot isn't set up yet (no bot token).") unless TelegramBot.configured?

    TelegramLink.start!(current_pool)
    redirect_to edit_pool_path, notice: "Tap the Telegram link below, then press Start in Telegram."
  end

  def destroy
    current_pool.update!(telegram_chat_id: nil, telegram_linked_at: nil, telegram_link_token: nil)
    redirect_to edit_pool_path, notice: "Telegram disconnected."
  end
end
