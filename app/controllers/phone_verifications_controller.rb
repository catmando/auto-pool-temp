class PhoneVerificationsController < ApplicationController
  # Send (or resend) a code. Twilio only says "queued" at first; carriers
  # usually accept or reject within a few seconds, so wait briefly to report it.
  def create
    message = PhoneVerification.new(current_pool).send_code!
    message.await_delivery_status!
    if message.failed?
      redirect_to edit_pool_path, alert: "The code text wasn't delivered. #{message.error}"
    else
      redirect_to edit_pool_path, notice: "Code sent to #{current_pool.phone_number} (#{message.status}). Enter it below."
    end
  rescue PhoneVerification::Error => e
    redirect_to edit_pool_path, alert: e.message
  end

  # Check the code the user gives back
  def update
    verification = PhoneVerification.new(current_pool)
    if verification.confirm(params[:code])
      redirect_to edit_pool_path, notice: "Phone number confirmed."
    else
      redirect_to edit_pool_path, alert: verification.failure_reason
    end
  end
end
