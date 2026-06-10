class ExercisesController < ApplicationController
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

  def exercise_params
    params.require(:exercise).permit(:name, :modality, :default_unit, :is_compound)
  end
end
