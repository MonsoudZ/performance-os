class OnboardingController < ApplicationController
  def show
    @goal = Current.user.active_goal
    @has_target = Current.user.exercise_prescriptions.exists?
    @has_checkin = Current.user.daily_readiness_inputs.exists?
    @has_device = Current.user.wearable_devices.active.exists?
    @complete = @goal.present? && (@has_target || @has_checkin)
  end
end
