class EmailVerificationsController < ApplicationController
  # The link lands from an email client, which may not carry the session cookie —
  # and the token is the proof, not the session.
  allow_unauthenticated_access only: :show

  def show
    user = User.find_by_token_for(:email_verification, params[:token])

    if user.nil?
      redirect_to root_path, alert: "That confirmation link has expired or has already been used."
      return
    end

    user.verify!
    redirect_to root_path, notice: "Email confirmed. Thanks."
  end

  def create
    if Current.user.verified?
      redirect_to root_path, notice: "That address is already confirmed."
      return
    end

    EmailVerificationsMailer.verify(Current.user).deliver_later
    redirect_to root_path, notice: "Confirmation sent. Check #{Current.user.email_address}."
  end
end
