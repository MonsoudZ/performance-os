class DashboardController < ApplicationController
  def show
    @user = Current.user
    today = @user.local_date
    @today_input = @user.daily_readiness_inputs.find_by(metric_date: today)
    @readiness_score = @user.readiness_scores.find_by(score_date: today)
    @decision = @user.coaching_decisions
      .where(decision_type: "daily_training")
      .where("inputs ->> 'plan_date' = ?", today.iso8601)
      .order(created_at: :desc)
      .first
    @decision_links = @decision&.child_links&.includes(:child_decision)&.order(:role, :id) || []
    @recent_workouts = @user.workout_sessions.includes(:set_entries).order(performed_at: :desc).limit(3)
    @active_prescriptions = @user.exercise_prescriptions.active_on(today).includes(:exercise).order("exercises.name")
    @today_templates = @user.workout_templates
      .scheduled_on(today)
      .includes(workout_template_exercises: :exercise)
      .order(:name)
    @wearable_device = @user.wearable_devices.active.order(last_synced_at: :desc).first
  end
end
