# Run a check right now: either a preview (no text, setpoint untouched) or a
# real check that texts if a change is needed.
class ChecksController < ApplicationController
  def create
    notify = params[:notify] == "1"
    check = PoolCheck.call(current_pool, notify: notify)
    rec = check.recommendation
    notice =
      if check.text_message&.failed? then "Recommended #{rec.target_temp}°F, but the text failed: #{check.text_message.error}"
      elsif check.notified? then "Recommended #{rec.target_temp}°F and sent a text."
      elsif notify && !current_pool.needs_change?(rec.target_temp) then "Recommended #{rec.target_temp}°F. No change needed, so no text was sent."
      else "Recommended #{rec.target_temp}°F (preview, nothing sent)."
      end
    redirect_to root_path, notice: notice
  rescue Weather::OpenMeteo::Error, ArgumentError => e
    redirect_to root_path, alert: "Check failed: #{e.message}"
  end
end
