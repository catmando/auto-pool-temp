# When this app process started. Plans made before it may come from older
# planner code (a deploy), so the dashboard re-plans them.
Rails.application.config.booted_at = Time.current
