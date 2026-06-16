class AddTrainingProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :experience_level, :string, null: false, default: "intermediate"
    add_column :users, :training_days_per_week, :integer, null: false, default: 4
    add_column :users, :available_equipment, :string, array: true, null: false,
      default: %w[barbell dumbbell machine bodyweight cable other]

    add_check_constraint :users,
      "experience_level IN ('beginner', 'intermediate', 'advanced')",
      name: "users_experience_level_check"
    add_check_constraint :users,
      "training_days_per_week BETWEEN 1 AND 7",
      name: "users_training_days_check"
  end
end
