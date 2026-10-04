class PoolsController < ApplicationController
  def edit
  end

  # Settings save as you change them (JSON, from the autosave controller), or
  # with the Save button.
  def update
    saved = current_pool.update(pool_params)
    respond_to do |format|
      format.json do
        if saved
          render json: { ok: true }
        else
          render json: { errors: current_pool.errors.full_messages }, status: :unprocessable_entity
        end
      end
      format.html { saved ? redirect_after_save : render(:edit, status: :unprocessable_entity) }
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
                           heat_rate_per_hour cool_rate_per_hour pump_on_1 pump_off_1 pump_on_2 pump_off_2
                           checks_per_day min_change notifications_enabled strategy])
  end
end
