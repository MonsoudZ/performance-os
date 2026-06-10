class ExercisePrescriptionsController < ApplicationController
  before_action :set_prescription, only: %i[edit update finish]

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

    if @prescription.valid?
      # One active prescription per exercise (partial unique index); creating a
      # new target for the same lift retires the current one.
      ApplicationRecord.transaction do
        supersede_active_prescription(@prescription)
        @prescription.save!
      end
      recompute_training_plan
      redirect_to exercise_prescriptions_path, notice: "Training target saved."
    else
      @exercises = Exercise.available_to(Current.user)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @prescription.update(prescription_params.except(:exercise_id))
      recompute_training_plan
      redirect_to exercise_prescriptions_path, notice: "Training target updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def finish
    @prescription.update!(ended_on: [ Current.user.local_date - 1.day, @prescription.started_on ].max)
    recompute_training_plan
    redirect_to exercise_prescriptions_path, notice: "Training target ended."
  end

  private

  def set_prescription
    @prescription = Current.user.exercise_prescriptions.find(params[:id])
  end

  def supersede_active_prescription(prescription)
    Current.user.exercise_prescriptions
      .active
      .where(exercise_id: prescription.exercise_id)
      .find_each do |existing|
        existing.update!(ended_on: [ prescription.started_on - 1.day, existing.started_on ].max)
      end
  end

  def recompute_training_plan
    TrainingPlanRecomputeJob.perform_later(Current.user, Current.user.local_date)
  end

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
