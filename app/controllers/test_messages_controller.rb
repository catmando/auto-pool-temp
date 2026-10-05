# "Send test message" (Advanced settings): see how alerts arrive, end to end.
class TestMessagesController < ApplicationController
  BODY = "Auto Pool Temp test message: alerts reach you here. Try replying STATUS.".freeze

  def create
    pool = current_pool
    unless pool.contact_verified?
      return redirect_to edit_pool_path(anchor: "advanced"), alert: "Connect Telegram first, then send a test message."
    end

    message = TextMessage.deliver(pool: pool, body: BODY)
    if message.failed?
      redirect_to edit_pool_path(anchor: "advanced"), alert: "The test message failed: #{message.error}"
    else
      redirect_to edit_pool_path(anchor: "advanced"), notice: "Test message sent by #{pool.channel_label}. Check your phone."
    end
  end
end
