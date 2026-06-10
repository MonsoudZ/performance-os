class WorkoutSessionsController < ApplicationController
  def new
    @workout_session = Current.user.workout_sessions.new(performed_at: Time.current)
    @workout_template = requested_workout_template
    prepare_workout_log
  end

  def create
    @workout_session = Current.user.workout_sessions.new(workout_session_params)
    @workout_template = requested_workout_template
    assign_template_snapshot

    if @workout_session.save
      decisions = DoubleProgressionEvaluator.new(@workout_session).call
      if Current.user.local_date_at(@workout_session.performed_at) == Current.user.local_date
        DailyTrainingOrchestrator.new(Current.user).call
      end
      notice = decisions.any? ? "Workout saved and progression evaluated." : "Workout saved."
      redirect_to workout_session_path(@workout_session), notice: notice
    else
      prepare_workout_log
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

  def prepare_workout_log
    log_date = Current.user.local_date_at(@workout_session.performed_at || Time.current)
    @prescriptions = Current.user.exercise_prescriptions.active_on(log_date).includes(:exercise).order("exercises.name")
    @set_contexts = WorkoutLogPrefill.new(
      Current.user,
      workout_session: @workout_session,
      log_date:,
      workout_template: @workout_template
    ).call
  end

  def requested_workout_template
    template_id = params[:workout_template_id] || params.dig(:workout_session, :workout_template_id)
    Current.user.workout_templates.find_by(id: template_id)
  end

  def assign_template_snapshot
    return unless @workout_template

    log_date = Current.user.local_date_at(@workout_session.performed_at)
    @workout_session.workout_template = @workout_template
    @workout_session.template_snapshot = WorkoutTemplateSnapshot.new(@workout_template, log_date:).call
  end

  def workout_session_params
    params.require(:workout_session).permit(
      :performed_at,
      :session_rpe,
      :notes,
      set_entries_attributes: [ :exercise_id, :set_index, :weight_kg, :reps, :rir, :is_warmup ]
    )
  end
end
