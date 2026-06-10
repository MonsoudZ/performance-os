class IndexCoachingDecisionsExerciseLookup < ActiveRecord::Migration[8.1]
  # Expression index for the per-exercise progression lookups that run in a loop
  # in DailyTrainingOrchestrator#progression_decisions and
  # WorkoutLogPrefill#latest_progression_weight. Without it, every
  # `inputs ->> 'exercise_id' = ?` filter scans a user's decisions.
  def change
    add_index :coaching_decisions,
      "user_id, decision_type, (inputs ->> 'exercise_id'), created_at",
      name: "index_decisions_on_user_type_exercise_created_at"
  end
end
