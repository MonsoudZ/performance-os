class AddProgressionModelToExercisePrescriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :exercise_prescriptions, :progression_model, :string,
      null: false, default: "double_progression"
    add_check_constraint :exercise_prescriptions,
      "progression_model IN ('double_progression', 'top_set')",
      name: "exercise_prescriptions_progression_model_check"
  end
end
