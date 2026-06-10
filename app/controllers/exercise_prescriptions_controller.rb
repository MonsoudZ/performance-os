class ExercisePrescriptionsController < ApplicationController
  def index
    @prescriptions = Current.user.exercise_prescriptions.active_on(Current.user.local_date).includes(:exercise).order("exercises.name")
  end

  def new
    @prescription = Current.user.exercise_prescriptions.new(
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      progression_model: "double_progression",
      started_on: Current.user.local_date
    )
    @exercises = Exercise.available_to(Current.user)
  end

  def create
    @prescription = Current.user.exercise_prescriptions.new(prescription_params)

    if @prescription.save
      DailyTrainingOrchestrator.new(Current.user).call
      redirect_to exercise_prescriptions_path, notice: "Prescription created."
    else
      @exercises = Exercise.available_to(Current.user)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def prescription_params
    params.require(:exercise_prescription).permit(
      :exercise_id,
      :rep_min,
      :rep_max,
      :target_rir_min,
      :target_rir_max,
      :increment_kg,
      :working_sets,
      :progression_model,
      :started_on
    )
  end
end
