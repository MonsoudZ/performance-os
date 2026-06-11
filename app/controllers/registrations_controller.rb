class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @user = User.new(time_zone: "UTC")
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for(@user)
      redirect_to onboarding_path, notice: "Welcome to PerformanceOS."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation, :unit_system, :time_zone)
  end
end
