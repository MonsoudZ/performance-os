class ConditioningSessionsController < ApplicationController
  include TrainingRecomputable

  def index
    load_workspace
  end

  def create
    @conditioning_session = Current.user.conditioning_sessions.new(conditioning_params)

    if @conditioning_session.save
      recompute_training_plan
      redirect_to conditioning_sessions_path, notice: "#{@conditioning_session.activity_type.humanize} session logged."
    else
      load_workspace
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    session = Current.user.conditioning_sessions.find(params[:id])
    session.destroy!
    recompute_training_plan
    redirect_to conditioning_sessions_path, notice: "Session removed."
  end

  private

  def load_workspace
    service = WeeklyConditioningSummary.new(Current.user)
    @week_start = service.week_start
    @week_end = service.week_end
    @summary = service.call
    @active_goal = Current.user.active_goal
    @sessions = Current.user.conditioning_sessions.order(performed_at: :desc).limit(15)
    @conditioning_session ||= Current.user.conditioning_sessions.new(performed_at: Time.current, activity_type: "run")
  end

  def conditioning_params
    params.require(:conditioning_session).permit(
      :activity_type, :performed_at, :duration_minutes, :distance_km, :avg_hr_bpm, :notes
    )
  end
end
