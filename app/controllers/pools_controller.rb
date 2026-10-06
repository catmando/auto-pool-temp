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

  # Alerts only go to a confirmed address, so steer the user to confirm one: a
  # new phone number gets a code texted right away.
  def redirect_after_save
    pool = current_pool
    if pool.contact_verified? || !pool.notifications_enabled?
      redirect_to root_path, notice: "Settings saved."
    elsif pool.notification_channel == "sms" && pool.phone_number.present?
      send_phone_code(pool)
    else
      redirect_to edit_pool_path(anchor: "delivery"), notice: "Settings saved. Connect Telegram to start getting alerts."
    end
  end

  def send_phone_code(pool)
    message = PhoneVerification.new(pool).send_code!
    message.await_delivery_status!
    if message.failed?
      redirect_to edit_pool_path(anchor: "delivery"), alert: "Settings saved, but the code text wasn't delivered. #{message.error}"
    else
      redirect_to edit_pool_path(anchor: "delivery"), notice: "Settings saved. We texted a code to #{pool.phone_number}. Enter it below."
    end
  rescue PhoneVerification::Error => e
    redirect_to edit_pool_path(anchor: "delivery"), alert: "Settings saved. #{e.message}"
  end

  def pool_params
    params.expect(pool: %i[name comfort_adjustment hot_air_temp hot_pool_temp cold_air_temp cold_pool_temp warm_day_threshold
                           heat_rate_per_hour cooling_factor has_cover pump_on_1 pump_off_1 pump_on_2 pump_off_2
                           checks_per_day min_change pump_boost_threshold notifications_enabled strategy
                           notification_channel phone_number sms_consent])
  end
end
