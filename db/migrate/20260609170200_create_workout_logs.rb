class CreateWorkoutLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_sessions do |table|
      table.references :user, null: false, foreign_key: true
      table.datetime :performed_at, null: false
      table.integer :duration_seconds
      table.decimal :session_rpe, precision: 3, scale: 1
      table.text :notes

      table.timestamps
    end
    add_index :workout_sessions, [ :user_id, :performed_at ]
    add_check_constraint :workout_sessions,
      "session_rpe IS NULL OR session_rpe BETWEEN 0 AND 10",
      name: "workout_sessions_rpe_check"

    create_table :set_entries do |table|
      table.references :workout_session, null: false, foreign_key: { on_delete: :cascade }
      table.references :exercise, null: false, foreign_key: true
      table.integer :set_index, null: false
      table.decimal :weight_kg, precision: 6, scale: 2
      table.integer :reps
      table.decimal :rir, precision: 3, scale: 1
      table.decimal :rpe, precision: 3, scale: 1
      table.boolean :is_warmup, null: false, default: false
      table.virtual :estimated_1rm_kg,
        type: :decimal,
        precision: 7,
        scale: 2,
        as: "weight_kg * (1 + reps::numeric / 30)",
        stored: true

      table.timestamps
    end
    add_index :set_entries, [ :workout_session_id, :exercise_id, :set_index ],
      unique: true,
      name: "index_set_entries_on_session_exercise_and_index"
    add_index :set_entries, [ :exercise_id, :created_at ]
    add_check_constraint :set_entries, "set_index > 0", name: "set_entries_index_check"
    add_check_constraint :set_entries, "reps IS NULL OR reps > 0", name: "set_entries_reps_check"
    add_check_constraint :set_entries, "rir IS NULL OR rir >= 0", name: "set_entries_rir_check"
    add_check_constraint :set_entries,
      "rpe IS NULL OR rpe BETWEEN 0 AND 10",
      name: "set_entries_rpe_check"
  end
end
