class CreateExercisePrescriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_prescriptions do |table|
      table.references :user, null: false, foreign_key: true
      table.references :exercise, null: false, foreign_key: true
      table.integer :rep_min, null: false
      table.integer :rep_max, null: false
      table.decimal :target_rir_min, precision: 3, scale: 1, null: false
      table.decimal :target_rir_max, precision: 3, scale: 1, null: false
      table.decimal :increment_kg, precision: 5, scale: 2, null: false
      table.integer :working_sets, null: false
      table.date :started_on, null: false
      table.date :ended_on

      table.timestamps
    end

    add_index :exercise_prescriptions,
      [ :user_id, :exercise_id ],
      unique: true,
      where: "ended_on IS NULL",
      name: "index_active_prescription_per_user_exercise"
    add_check_constraint :exercise_prescriptions,
      "rep_min > 0 AND rep_max >= rep_min",
      name: "exercise_prescriptions_rep_range_check"
    add_check_constraint :exercise_prescriptions,
      "target_rir_min >= 0 AND target_rir_max >= target_rir_min",
      name: "exercise_prescriptions_rir_range_check"
    add_check_constraint :exercise_prescriptions,
      "increment_kg > 0 AND working_sets > 0",
      name: "exercise_prescriptions_progression_check"
    add_check_constraint :exercise_prescriptions,
      "ended_on IS NULL OR ended_on >= started_on",
      name: "exercise_prescriptions_dates_check"
  end
end
