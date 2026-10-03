class TextMessagesController < ApplicationController
  def index
    @text_messages = current_pool.text_messages.recent.limit(200)
  end
end
