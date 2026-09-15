# A workout as the phone needs it: which lifts, in which order, and what each
# one is being asked to do today.
#
# The targets come from `TrainingTargets` rather than off the prescription,
# because a training block owns the scheme and the prescription is only the
# baseline — printing `rep_min` here would describe a past target as if it were
# the present one. A lift with no prescription still ships, with null targets:
# the client can log it, and `uncovered` says plainly that the progression
# engine will not evaluate it.
class WorkoutTemplateSerializer
  def initialize(template, targets:)
    @template = template
    @targets = targets
  end

  def as_json(*)
    {
      id: template.id,
      name: template.name,
      weekdays: template.weekdays,
      exercises: items.map { |item| exercise_json(item) }
    }
  end

  private

  attr_reader :template, :targets

  def items
    template.workout_template_exercises.sort_by(&:position)
  end

  def exercise_json(item)
    resolved = targets.for(item.exercise)

    {
      position: item.position,
      exercise: ExerciseSummarySerializer.new(item.exercise).as_json,
      uncovered: resolved.nil?,
      targets: resolved && {
        working_sets: resolved.working_sets,
        rep_min: resolved.rep_min,
        rep_max: resolved.rep_max,
        target_rir_min: resolved.target_rir_min.to_f,
        target_rir_max: resolved.target_rir_max.to_f,
        source: resolved.source.to_s
      }
    }
  end
end
