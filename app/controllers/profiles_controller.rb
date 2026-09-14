class ProfilesController < ApplicationController
  include MeasurementParams
  def edit
    @user = Current.user
  end

  def update
    if Current.user.update(profile_params)
      redirect_back fallback_location: edit_profile_path, notice: "Profile updated."
    else
      redirect_back fallback_location: edit_profile_path,
        alert: Current.user.errors.full_messages.to_sentence
    end
  end

  # Deleting an account is irreversible and takes every log, decision and
  # measurement with it, so it asks for the password rather than a confirm
  # dialog: a dialog only proves someone clicked, and a session left open on a
  # shared machine can click.
  def destroy
    user = Current.user

    unless user.authenticate(params[:password].to_s)
      redirect_to edit_profile_path, alert: "That password is not right, so nothing was deleted."
      return
    end

    AccountDeletion.new(user).call
    # The session rows went with the account; the cookie pointing at one has to
    # go too or the next request tries to resume a session that no longer exists.
    cookies.delete(:session_id)
    Current.session = nil
    redirect_to new_session_path, status: :see_other,
      notice: "Your account and everything in it has been deleted."
  end

  private

  def profile_params
    to_canonical_units(
      params.require(:user).permit(
        :experience_level,
        :training_days_per_week,
        :sex,
        :birth_date,
        :height_cm,
        :unit_system,
        :time_zone,
        :max_hr,
        available_equipment: []
      ),
      lengths: [ :height_cm ]
    )
  end
end
