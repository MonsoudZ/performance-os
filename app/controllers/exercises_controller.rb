class ExercisesController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @modality = params[:modality].presence_in(Exercise::MODALITIES)
    @exercises = filtered_exercises
    @prescribed_exercise_ids = Current.user.exercise_prescriptions.active.pluck(:exercise_id).to_set
    @last_performed = last_performed_by_exercise
  end

  def show
    @exercise = Exercise.available_to(Current.user).find(params[:id])
    @history = ExerciseHistory.new(Current.user, @exercise)
    @progress = StrengthProgression.new(Current.user, exercise: @exercise).call.first
  end

  def new
    @exercise = Current.user.exercises.new(modality: "barbell", default_unit: "kg")
  end

  def create
    @exercise = Current.user.exercises.new(exercise_params)

    if @exercise.save
      redirect_to new_exercise_prescription_path, notice: "#{@exercise.name} added. Set a target for it below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def filtered_exercises
    scope = Exercise.available_to(Current.user).includes(exercise_muscle_contributions: :muscle_group)
    scope = scope.where("exercises.name ILIKE ?", "%#{Exercise.sanitize_sql_like(@query)}%") if @query.present?
    scope = scope.where(modality: @modality) if @modality
    scope
  end

  # One grouped query for the whole list rather than a date lookup per card.
  def last_performed_by_exercise
    SetEntry
      .joins(:workout_session)
      .where(workout_sessions: { user_id: Current.user.id })
      .group(:exercise_id)
      .maximum("workout_sessions.performed_at")
      .transform_values { |performed_at| Current.user.local_date_at(performed_at) }
  end

  def exercise_params
    params.require(:exercise).permit(:name, :modality, :default_unit, :is_compound)
  end
end
