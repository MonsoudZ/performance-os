class WorkoutSessionsController < ApplicationController
  def new
    @prescriptions = Current.user.exercise_prescriptions.active_on(Current.user.local_date).includes(:exercise).order("exercises.name")
    @workout_session = Current.user.workout_sessions.new(performed_at: Time.current)
    5.times { @workout_session.set_entries.build }
  end

  def create
    @workout_session = Current.user.workout_sessions.new(workout_session_params)

    if @workout_session.save
      decisions = DoubleProgressionEvaluator.new(@workout_session).call
      if Current.user.local_date_at(@workout_session.performed_at) == Current.user.local_date
        DailyTrainingOrchestrator.new(Current.user).call
      end
      notice = decisions.any? ? "Workout saved and progression evaluated." : "Workout saved."
      redirect_to workout_session_path(@workout_session), notice: notice
    else
      @prescriptions = Current.user.exercise_prescriptions.active_on(Current.user.local_date).includes(:exercise).order("exercises.name")
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @workout_session = Current.user.workout_sessions.includes(set_entries: :exercise).find(params[:id])
    @set_entries = @workout_session.set_entries.sort_by(&:set_index)
    @decisions = Current.user.coaching_decisions
      .where(decision_type: "double_progression")
      .where("inputs ->> 'workout_session_id' = ?", @workout_session.id.to_s)
      .order(:created_at)
  end

  private

  def workout_session_params
    params.require(:workout_session).permit(
      :performed_at,
      :session_rpe,
      :notes,
      set_entries_attributes: [ :exercise_id, :set_index, :weight_kg, :reps, :rir, :is_warmup ]
    )
  end
end
