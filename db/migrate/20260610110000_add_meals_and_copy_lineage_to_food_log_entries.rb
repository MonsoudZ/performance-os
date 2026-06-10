class AddMealsAndCopyLineageToFoodLogEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :food_log_entries, :meal_type, :string, null: false, default: "snack"
    add_reference :food_log_entries,
      :copied_from_entry,
      foreign_key: { to_table: :food_log_entries },
      index: { unique: true }

    add_check_constraint :food_log_entries,
      "meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')",
      name: "food_log_entries_meal_type_check"
  end
end
