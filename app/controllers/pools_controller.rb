class PoolsController < ApplicationController
  def edit
  end

  def update
    if current_pool.update(pool_params)
      redirect_after_save
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # Alerts only go to a confirmed Telegram chat, so steer the user to connect one.
  def redirect_after_save
    if current_pool.contact_verified? || !current_pool.notifications_enabled?
      redirect_to root_path, notice: "Settings saved."
    else
      redirect_to edit_pool_path(anchor: "delivery"), notice: "Settings saved. Connect Telegram to start getting alerts."
    end
  end

  def pool_params
    params.expect(pool: %i[name hot_air_temp hot_pool_temp cold_air_temp cold_pool_temp warm_day_threshold
                           heat_rate_per_day cool_rate_per_day checks_per_day min_change notifications_enabled strategy])
  end
end
