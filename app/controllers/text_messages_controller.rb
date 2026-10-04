class TextMessagesController < ApplicationController
  def index
    @text_messages = current_pool.text_messages.recent.limit(200)
    # Pick up carrier results for recent texts Twilio hadn't finalized yet.
    @text_messages.select(&:delivery_pending?).first(10).each(&:refresh_delivery_status!)
  end
end
