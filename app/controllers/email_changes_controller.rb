class EmailChangesController < ApplicationController
  # The link lands from an email client, which may carry no session — and the
  # account being moved is often not the one signed in on that device.
  allow_unauthenticated_access only: :show

  def create
    result = EmailChangeRequest.new(
      Current.user,
      new_address: params[:email_address],
      password: params[:password]
    ).call

    if result.success?
      redirect_to edit_profile_path,
        notice: "Confirm the change at #{Current.user.pending_email_address}. " \
          "Until you do, this account keeps #{Current.user.email_address}."
    else
      redirect_to edit_profile_path, alert: result.error
    end
  end

  def show
    result = EmailChangeConfirmation.new(params[:token]).call

    case result.error
    when nil
      redirect_to root_path, notice: "Your email address is now #{result.user.email_address}."
    when :taken
      redirect_to root_path, alert: "That address was claimed by another account, so the change was cancelled."
    else
      redirect_to root_path, alert: "That link has expired or has already been used."
    end
  end

  def destroy
    Current.user.update!(pending_email_address: nil)
    redirect_to edit_profile_path, notice: "The pending email change was cancelled."
  end
end
