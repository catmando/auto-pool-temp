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

  # Alerts only go to a confirmed address, so steer the user to confirm one.
  def redirect_after_save
    pool = current_pool
    if pool.contact_verified? || !pool.notifications_enabled?
      redirect_to root_path, notice: "Settings saved."
    elsif pool.notification_channel == "sms" && pool.saved_change_to_phone_number? && pool.phone_number.present?
      begin
        PhoneVerification.new(pool).send_code!
        redirect_to edit_pool_path, notice: "Settings saved. We texted a code to #{pool.phone_number}. Enter it below."
      rescue PhoneVerification::Error => e
        redirect_to edit_pool_path, alert: "Settings saved, but the confirmation code wasn't sent: #{e.message}"
      end
    else
      redirect_to edit_pool_path, notice: "Settings saved. Confirm where alerts should go (below) to start getting them."
    end
  end

  def pool_params
    params.expect(pool: %i[name location_name latitude longitude time_zone
                           hot_air_temp hot_pool_temp cold_air_temp cold_pool_temp
                           heat_rate_per_day cool_rate_per_day
                           notification_channel phone_number checks_per_day min_change notifications_enabled
                           strategy forecast_days])
  end
end
