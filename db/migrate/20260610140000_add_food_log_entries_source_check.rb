class AddFoodLogEntriesSourceCheck < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :food_log_entries,
      "source IN ('manual', 'copy')",
      name: "food_log_entries_source_check"
  end
end
