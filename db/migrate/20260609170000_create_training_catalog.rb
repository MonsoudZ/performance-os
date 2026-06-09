class CreateTrainingCatalog < ActiveRecord::Migration[8.1]
  def change
    create_table :muscle_groups do |table|
      table.string :name, null: false

      table.timestamps
    end
    add_index :muscle_groups, :name, unique: true

    create_table :exercises do |table|
      table.references :user, foreign_key: true
      table.string :name, null: false
      table.string :modality, null: false
      table.boolean :is_compound, null: false, default: false
      table.string :default_unit, null: false, default: "kg"

      table.timestamps
    end
    add_index :exercises, [ :user_id, :name ], unique: true
    add_check_constraint :exercises,
      "modality IN ('barbell', 'dumbbell', 'machine', 'bodyweight', 'cable', 'other')",
      name: "exercises_modality_check"
    add_check_constraint :exercises,
      "default_unit IN ('kg', 'reps', 'seconds', 'meters')",
      name: "exercises_default_unit_check"

    create_table :exercise_muscle_contributions, id: false do |table|
      table.references :exercise, null: false, foreign_key: true
      table.references :muscle_group, null: false, foreign_key: true
      table.string :role, null: false
      table.decimal :fraction, precision: 3, scale: 2, null: false
    end
    add_index :exercise_muscle_contributions,
      [ :exercise_id, :muscle_group_id ],
      unique: true,
      name: "index_exercise_muscle_contributions_unique"
    add_check_constraint :exercise_muscle_contributions,
      "role IN ('primary', 'secondary')",
      name: "exercise_muscle_contributions_role_check"
    add_check_constraint :exercise_muscle_contributions,
      "fraction > 0 AND fraction <= 1",
      name: "exercise_muscle_contributions_fraction_check"
  end
end
