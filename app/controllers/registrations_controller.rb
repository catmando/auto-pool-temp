# Sign-up is only open until the first account exists (single-user for now).
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_open_registration

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[email_address password password_confirmation]))
    if @user.save
      start_new_session_for @user
      redirect_to edit_pool_path, notice: "Welcome! Set up your pool to get started."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def require_open_registration
    redirect_to new_session_path, alert: "Registration is closed." if User.exists?
  end
end
