class CreateWorkoutTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_templates do |table|
      table.references :user, null: false, foreign_key: true
      table.string :name, null: false
      table.integer :weekdays, array: true, default: [], null: false

      table.timestamps
    end
    add_index :workout_templates, [ :user_id, :name ], unique: true

    create_table :workout_template_exercises do |table|
      table.references :workout_template, null: false, foreign_key: true
      table.references :exercise, null: false, foreign_key: true
      table.integer :position, null: false

      table.timestamps
    end
    add_index :workout_template_exercises,
      [ :workout_template_id, :exercise_id ],
      unique: true,
      name: "index_template_exercises_unique"
    add_index :workout_template_exercises,
      [ :workout_template_id, :position ],
      name: "index_template_exercises_position"
    add_check_constraint :workout_template_exercises,
      "position > 0",
      name: "workout_template_exercises_position_check"

    add_reference :workout_sessions, :workout_template, foreign_key: true
    add_column :workout_sessions, :template_snapshot, :jsonb, default: {}, null: false
  end
end
