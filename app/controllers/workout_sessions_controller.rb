class WorkoutSessionsController < ApplicationController
  include TrainingRecomputable

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
      WorkoutProgressionRecomputeJob.perform_later(@workout_session)
      redirect_to workout_session_path(@workout_session), notice: "Workout saved. Evaluating progression…"
    else
      prepare_workout_log
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @workout_session = Current.user.workout_sessions.includes(set_entries: :exercise).find(params[:id])
    @set_entries = @workout_session.set_entries.sort_by(&:set_index)
    # Editing re-evaluates progression and writes a fresh decision, so show only
    # the latest decision per exercise.
    @decisions = Current.user.coaching_decisions
      .active_evidence
      .of_type("double_progression")
      .for_input("workout_session_id", @workout_session.id)
      .latest_first
      .to_a
      .uniq { |decision| decision.inputs["exercise_id"] }
  end

  def edit
    @workout_session = Current.user.workout_sessions.includes(set_entries: :exercise).find(params[:id])
    @set_entries = @workout_session.set_entries.sort_by(&:set_index)
  end

  def update
    @workout_session = Current.user.workout_sessions.find(params[:id])

    if @workout_session.update(workout_session_params)
      WorkoutProgressionRetractor.new(
        @workout_session,
        reason: "workout_session_corrected"
      ).call
      WorkoutProgressionRecomputeJob.perform_later(@workout_session)
      redirect_to workout_session_path(@workout_session), notice: "Workout updated. Re-evaluating progression…"
    else
      @set_entries = @workout_session.set_entries.sort_by(&:set_index)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    workout_session = Current.user.workout_sessions.find(params[:id])
    WorkoutProgressionRetractor.new(
      workout_session,
      reason: "workout_session_deleted"
    ).call
    workout_session.destroy!
    recompute_training_plan
    redirect_to root_path, notice: "Workout deleted."
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
      set_entries_attributes: [ :id, :exercise_id, :set_index, :weight_kg, :reps, :rir, :is_warmup, :_destroy ]
    )
  end
end
