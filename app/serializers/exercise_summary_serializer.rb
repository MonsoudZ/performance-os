# Just enough of an exercise to name it in a list. The full catalog entry, with
# muscle contributions, is what /api/v1/exercises is for.
class ExerciseSummarySerializer
  def initialize(exercise)
    @exercise = exercise
  end

  def as_json(*)
    {
      id: exercise.id,
      name: exercise.name,
      modality: exercise.modality,
      default_unit: exercise.default_unit
    }
  end

  private

  attr_reader :exercise
end
