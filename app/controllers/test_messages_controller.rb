# "Send test message" (Advanced settings): sends exactly the alert the current
# plan would send right now, so you can see a real one. It's only a test, so it
# doesn't change what the app assumes the heater, cover, or pump are set to.
class TestMessagesController < ApplicationController
  def create
    pool = current_pool
    unless pool.contact_verified?
      return redirect_to edit_pool_path(anchor: "advanced"), alert: "Connect Telegram first, then send a test message."
    end

    plan = CurrentPlan.for(pool)
    return redirect_to(edit_pool_path(anchor: "advanced"), alert: plan.error || "No plan yet.") unless plan.recommendation

    message = TextMessage.deliver(pool: pool, body: self.class.body_for(pool, plan.recommendation))
    if message.failed?
      redirect_to edit_pool_path(anchor: "advanced"), alert: "The test message failed: #{message.error}"
    else
      redirect_to edit_pool_path(anchor: "advanced"), notice: "Test message sent by #{pool.channel_label}: the alert your pool would get right now."
    end
  end

  # The alert text for a saved plan (PoolCheck builds the same text from a fresh result).
  def self.body_for(pool, recommendation)
    result = Recommenders::Result.new(raw_target: recommendation.target_temp, reason: recommendation.reason,
                                      details: (recommendation.details || {}).deep_symbolize_keys)
    PoolCheck.message_for(pool, result, pool.assumed_setpoint)
  end
end
