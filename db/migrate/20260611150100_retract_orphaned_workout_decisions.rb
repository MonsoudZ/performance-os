class RetractOrphanedWorkoutDecisions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE coaching_decisions
      SET retracted_at = CURRENT_TIMESTAMP,
          retraction_reason = 'source_workout_missing',
          updated_at = CURRENT_TIMESTAMP
      WHERE decision_type = 'double_progression'
        AND retracted_at IS NULL
        AND inputs ? 'workout_session_id'
        AND NOT EXISTS (
          SELECT 1
          FROM workout_sessions
          WHERE workout_sessions.id = (coaching_decisions.inputs ->> 'workout_session_id')::bigint
            AND workout_sessions.user_id = coaching_decisions.user_id
        )
    SQL

    execute <<~SQL
      WITH RECURSIVE invalid_decisions(id) AS (
        SELECT id
        FROM coaching_decisions
        WHERE retracted_at IS NOT NULL

        UNION

        SELECT links.parent_decision_id
        FROM coaching_decision_links links
        INNER JOIN invalid_decisions ON invalid_decisions.id = links.child_decision_id
      )
      UPDATE coaching_decisions
      SET retracted_at = CURRENT_TIMESTAMP,
          retraction_reason = 'derived_evidence_retracted',
          updated_at = CURRENT_TIMESTAMP
      WHERE id IN (SELECT id FROM invalid_decisions)
        AND retracted_at IS NULL
    SQL
  end

  def down
  end
end
