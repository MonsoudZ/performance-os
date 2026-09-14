class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @user = User.new(time_zone: "UTC")
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      EmailVerificationsMailer.verify(@user).deliver_later
      start_new_session_for(@user)
      # Signed straight in on purpose: a new account can start logging
      # immediately, and the one thing it cannot do until confirmed is spend
      # money. Walling off the whole app behind an email that may be slow,
      # filtered or misaddressed costs more than it protects.
      redirect_to onboarding_path,
        notice: "Welcome to PerformanceOS. Confirm your email when you get a moment."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation, :unit_system, :time_zone)
  end
end
