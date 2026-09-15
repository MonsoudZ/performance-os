class CreateMeals < ActiveRecord::Migration[8.1]
  # A named group of foods and portions somebody eats together, so logging
  # breakfast is one tap rather than four. The same idea as a workout template:
  # the thing you repeat is worth keeping once rather than rebuilding daily.
  def change
    create_table :meals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    # One name per person, like workout templates — "Breakfast" twice is a
    # mistake rather than two meals.
    add_index :meals, [ :user_id, :name ], unique: true

    create_table :meal_items do |t|
      t.references :meal, null: false, foreign_key: true
      t.references :food, null: false, foreign_key: true
      # Grams, like food_log_entries.quantity_grams — a meal stores portions,
      # not macros. Macros are recomputed from the food when it is logged, so a
      # corrected food corrects the meal rather than leaving it stale.
      t.decimal :quantity_grams, precision: 7, scale: 1, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :meal_items, [ :meal_id, :food_id ], unique: true
    add_index :meal_items, [ :meal_id, :position ]
    add_check_constraint :meal_items, "quantity_grams > 0", name: "meal_items_quantity_check"
    add_check_constraint :meal_items, "position > 0", name: "meal_items_position_check"

    # Where a logged entry came from, so the audit trail says "this was a meal"
    # rather than pretending each item was typed.
    remove_check_constraint :food_log_entries, name: "food_log_entries_source_check"
    add_check_constraint :food_log_entries, "source IN ('manual', 'copy', 'meal')",
      name: "food_log_entries_source_check"
  end
end
