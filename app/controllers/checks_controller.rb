# Run a check right now: either a preview (nothing sent, setpoint untouched)
# or a real check that sends an alert if a change is needed.
class ChecksController < ApplicationController
  def create
    notify = params[:notify] == "1"
    check = PoolCheck.call(current_pool, notify: notify)
    target = check.recommendation.target_temp
    notice =
      if check.text_message&.failed? then "Recommended #{target}°F, but the alert failed: #{check.text_message.error}"
      elsif check.notified? then "Recommended #{target}°F and sent an alert by #{current_pool.channel_label}."
      elsif !notify then "Recommended #{target}°F (preview, nothing sent)."
      elsif !current_pool.needs_change?(target) then "Recommended #{target}°F. No change needed, so no alert was sent."
      elsif !current_pool.notifications_enabled? then "Recommended #{target}°F. Alerts are paused, so nothing was sent."
      else "Recommended #{target}°F, but nothing was sent: confirm where alerts go in Settings first."
      end
    redirect_to root_path, notice: notice
  rescue Weather::OpenMeteo::Error, ArgumentError => e
    redirect_to root_path, alert: "Check failed: #{e.message}"
  end
end
