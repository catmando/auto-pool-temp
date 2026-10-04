class PhoneVerificationsController < ApplicationController
  # Send (or resend) a code
  def create
    PhoneVerification.new(current_pool).send_code!
    redirect_to edit_pool_path, notice: "Code sent to #{current_pool.phone_number}. Enter it below."
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
