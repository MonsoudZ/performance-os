class WorkoutTemplateSnapshot
  def initialize(template, log_date:)
    @template = template
    @log_date = log_date
  end

  def call
    targets = TrainingTargets.new(template.user, on: log_date)

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
          # The set count the block and the target together prescribe for this
          # day, frozen into the session so a later block change cannot rewrite
          # what a logged workout was asked for.
          "working_sets" => prescription ? targets.targets_for(prescription).working_sets : 1
        }
      end
    }
  end

  private

  attr_reader :template, :log_date
end
