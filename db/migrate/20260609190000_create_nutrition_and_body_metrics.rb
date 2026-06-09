class CreateNutritionAndBodyMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :foods do |table|
      table.references :user, foreign_key: true
      table.string :name, null: false
      table.string :brand
      table.string :barcode
      table.decimal :serving_grams, precision: 7, scale: 1, null: false
      table.decimal :kcal, precision: 7, scale: 1, null: false
      table.decimal :protein_g, precision: 6, scale: 1, null: false
      table.decimal :carb_g, precision: 6, scale: 1, null: false
      table.decimal :fat_g, precision: 6, scale: 1, null: false
      table.string :source, null: false, default: "manual"

      table.timestamps
    end
    add_index :foods, :barcode, where: "barcode IS NOT NULL"
    add_index :foods, [ :user_id, :name, :brand ]
    add_check_constraint :foods,
      "source IN ('manual', 'barcode', 'import', 'verified')",
      name: "foods_source_check"
    add_check_constraint :foods,
      "serving_grams > 0 AND kcal >= 0 AND protein_g >= 0 AND carb_g >= 0 AND fat_g >= 0",
      name: "foods_nutrition_values_check"

    create_table :food_log_entries do |table|
      table.references :user, null: false, foreign_key: true
      table.references :food, foreign_key: true
      table.datetime :logged_at, null: false
      table.decimal :quantity_grams, precision: 7, scale: 1, null: false
      table.decimal :kcal, precision: 7, scale: 1, null: false
      table.decimal :protein_g, precision: 6, scale: 1, null: false
      table.decimal :carb_g, precision: 6, scale: 1, null: false
      table.decimal :fat_g, precision: 6, scale: 1, null: false
      table.string :source, null: false, default: "manual"

      table.timestamps
    end
    add_index :food_log_entries, [ :user_id, :logged_at ]
    add_check_constraint :food_log_entries,
      "quantity_grams > 0 AND kcal >= 0 AND protein_g >= 0 AND carb_g >= 0 AND fat_g >= 0",
      name: "food_log_entries_values_check"

    create_table :body_metrics do |table|
      table.references :user, null: false, foreign_key: true
      table.date :measured_on, null: false
      table.decimal :weight_kg, precision: 6, scale: 2
      table.decimal :body_fat_pct, precision: 4, scale: 1
      table.string :source, null: false, default: "manual"

      table.timestamps
    end
    add_index :body_metrics, [ :user_id, :measured_on ]
    add_check_constraint :body_metrics,
      "weight_kg IS NULL OR weight_kg > 0",
      name: "body_metrics_weight_check"
    add_check_constraint :body_metrics,
      "body_fat_pct IS NULL OR body_fat_pct BETWEEN 0 AND 100",
      name: "body_metrics_body_fat_check"

    create_table :weight_trends, id: false do |table|
      table.references :user, null: false, foreign_key: true
      table.date :trend_date, null: false
      table.decimal :raw_kg, precision: 6, scale: 2
      table.decimal :ewma_kg, precision: 6, scale: 2, null: false

      table.timestamps
    end
    add_index :weight_trends, [ :user_id, :trend_date ], unique: true

    create_table :expenditure_estimates, id: false do |table|
      table.references :user, null: false, foreign_key: true
      table.date :estimate_date, null: false
      table.decimal :intake_kcal, precision: 7, scale: 1
      table.decimal :trend_weight_kg, precision: 6, scale: 2
      table.decimal :estimated_tdee, precision: 7, scale: 1, null: false
      table.string :confidence
      table.datetime :computed_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :expenditure_estimates, [ :user_id, :estimate_date ], unique: true
    add_check_constraint :expenditure_estimates,
      "confidence IN ('low', 'moderate', 'high')",
      name: "expenditure_estimates_confidence_check"
  end
end
