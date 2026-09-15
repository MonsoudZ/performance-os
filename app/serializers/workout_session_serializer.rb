# A logged session, in the order it was performed.
#
# `ordered_set_entries` rather than the raw association: `set_index` restarts at
# 1 for each lift, so sorting the whole session by it interleaves them.
#
# Weights are in kilograms, like everything else crossing this boundary. The
# client converts for display using the `unit_system` on the profile.
class WorkoutSessionSerializer
  def initialize(workout_session)
    @workout_session = workout_session
  end

  def as_json(*)
    {
      id: workout_session.id,
      performed_at: workout_session.performed_at.iso8601,
      template_name: workout_session.template_name,
      workout_template_id: workout_session.workout_template_id,
      session_rpe: workout_session.session_rpe,
      notes: workout_session.notes,
      sets: workout_session.ordered_set_entries.map { |entry| set_json(entry) }
    }
  end

  private

  attr_reader :workout_session

  def set_json(entry)
    {
      id: entry.id,
      exercise: ExerciseSummarySerializer.new(entry.exercise).as_json,
      set_index: entry.set_index,
      weight_kg: entry.weight_kg&.to_f,
      reps: entry.reps,
      rir: entry.rir&.to_f,
      warmup: entry.is_warmup?
    }
  end
end
