class ProfilesController < ApplicationController
  def update
    if Current.user.update(profile_params)
      redirect_back fallback_location: conditioning_sessions_path, notice: "Profile updated."
    else
      redirect_back fallback_location: conditioning_sessions_path,
        alert: Current.user.errors.full_messages.to_sentence
    end
  end

  private

  def profile_params
    params.require(:user).permit(:max_hr)
  end
end
