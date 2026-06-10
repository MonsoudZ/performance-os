class WorkoutTemplatesController < ApplicationController
  before_action :set_workout_template, only: %i[edit update destroy]

  def index
    @workout_templates = Current.user.workout_templates
      .includes(workout_template_exercises: :exercise)
      .order(:name)
  end

  def new
    @workout_template = Current.user.workout_templates.new
    @workout_template.workout_template_exercises.build(position: 1)
    prepare_form
  end

  def create
    @workout_template = Current.user.workout_templates.new(workout_template_params)
    normalize_positions

    if @workout_template.save
      redirect_to workout_templates_path, notice: "#{@workout_template.name} created."
    else
      prepare_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prepare_form
  end

  def update
    @workout_template.assign_attributes(workout_template_params)
    normalize_positions

    if @workout_template.save
      redirect_to workout_templates_path, notice: "#{@workout_template.name} updated."
    else
      prepare_form
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workout_template.destroy!
    redirect_to workout_templates_path, notice: "Workout template removed."
  end

  private

  def set_workout_template
    @workout_template = Current.user.workout_templates.find(params[:id])
  end

  def workout_template_params
    permitted = params.require(:workout_template).permit(
      :name,
      weekdays: [],
      workout_template_exercises_attributes: %i[id exercise_id position _destroy]
    )
    permitted[:weekdays] = Array(permitted[:weekdays]).reject(&:blank?).map(&:to_i)
    permitted
  end

  def normalize_positions
    @workout_template.workout_template_exercises
      .reject(&:marked_for_destruction?)
      .sort_by { |item| item.position || Float::INFINITY }
      .each_with_index { |item, index| item.position = index + 1 }
  end

  def prepare_form
    @exercises = Exercise.available_to(Current.user)
  end
end
