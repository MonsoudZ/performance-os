class WorkoutTemplateSnapshot
  def initialize(template, log_date:)
    @template = template
    @log_date = log_date
  end

  def call
    {
      "id" => template.id,
      "name" => template.name,
      "weekdays" => template.weekdays,
      "exercises" => template.workout_template_exercises.includes(:exercise).map do |item|
        prescription = template.user.exercise_prescriptions
          .where(exercise: item.exercise)
          .active_on(log_date)
          .order(started_on: :desc)
          .first

        {
          "exercise_id" => item.exercise_id,
          "exercise_name" => item.exercise.name,
          "position" => item.position,
          "working_sets" => prescription&.working_sets || 1
        }
      end
    }
  end

  private

  attr_reader :template, :log_date
end
