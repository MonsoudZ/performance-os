class ProfilesController < ApplicationController
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

  private

  def profile_params
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
    )
  end
end
