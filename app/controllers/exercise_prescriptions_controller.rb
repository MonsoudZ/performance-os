class ExercisePrescriptionsController < ApplicationController
  include TrainingRecomputable

  before_action :set_prescription, only: %i[edit update finish]

  def index
    # Ongoing targets (not yet ended), so a retired lift leaves the list at once
    # — even one ended the same day it started.
    @prescriptions = Current.user.exercise_prescriptions.active.includes(:exercise).order("exercises.name")
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
    ExercisePrescriptionSuperseder.new(
      @prescription,
      effective_on: Current.user.local_date
    ).call(prescription_params.except(:exercise_id, :started_on))

    recompute_training_plan
    redirect_to exercise_prescriptions_path, notice: "Training target updated."
  rescue ActiveRecord::RecordInvalid => error
    unless error.record.equal?(@prescription)
      error.record.errors.each do |validation_error|
        @prescription.errors.add(validation_error.attribute, validation_error.message)
      end
    end
    render :edit, status: :unprocessable_entity
  end

  def finish
    @prescription.update!(ended_on: @prescription.ended_on_for(Current.user.local_date))
    recompute_training_plan
    redirect_to exercise_prescriptions_path, notice: "Training target ended."
  end

  private

  def set_prescription
    @prescription = Current.user.exercise_prescriptions.active.find(params[:id])
  end

  def supersede_active_prescription(prescription)
    Current.user.exercise_prescriptions
      .active
      .where(exercise_id: prescription.exercise_id)
      .find_each do |existing|
        existing.update!(ended_on: existing.ended_on_for(prescription.started_on))
      end
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
