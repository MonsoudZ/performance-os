# What correcting or deleting a logged workout costs beyond the row itself.
#
# A workout is evidence: `DoubleProgressionEvaluator` reads it and writes a
# decision per lift. So changing one has to withdraw the decisions built on it,
# and the two cases differ in what happens next — a correction asks for new
# conclusions, a deletion does not replace the ones it takes back. Both go
# through `WorkoutProgressionRetractor`, which walks up the DAG so a weekly
# review resting on a withdrawn progression is withdrawn too.
#
# Shared so the reason strings and the recompute cannot drift between the web
# and the phone, which is how the same rule ended up meaning three things
# elsewhere in this app.
module WorkoutSessionWrites
  extend ActiveSupport::Concern
  include TrainingRecomputable

  private

  # The sets moved, so what was concluded from them is withdrawn and the
  # evaluator is asked again. "Withdrawn" is what the user reads; the record of
  # what was taken back stays in the table either way.
  def withdraw_and_reevaluate(workout_session)
    WorkoutProgressionRetractor.new(workout_session, reason: "workout_session_corrected").call
    WorkoutProgressionRecomputeJob.perform_later(workout_session)
  end

  # The evidence is gone, so nothing replaces the decisions it produced. The
  # day's plan is still recomposed, because it was built on a workout that no
  # longer exists.
  def withdraw_and_delete(workout_session)
    WorkoutProgressionRetractor.new(workout_session, reason: "workout_session_deleted").call
    workout_session.destroy!
    recompute_training_plan
  end
end
