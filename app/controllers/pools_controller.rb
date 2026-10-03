class PoolsController < ApplicationController
  def edit
  end

  def update
    if current_pool.update(pool_params)
      redirect_to root_path, notice: "Settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def pool_params
    params.expect(pool: %i[name location_name latitude longitude time_zone
                           hot_air_temp hot_pool_temp cold_air_temp cold_pool_temp
                           heat_rate_per_day cool_rate_per_day
                           phone_number checks_per_day min_change notifications_enabled
                           strategy forecast_days])
  end
end
