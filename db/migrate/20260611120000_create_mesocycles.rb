class CreateMesocycles < ActiveRecord::Migration[8.1]
  def change
    create_table :mesocycles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.date :started_on, null: false
      t.integer :weeks, null: false, default: 4
      t.integer :deload_week
      t.date :ended_on
      t.timestamps
    end

    add_index :mesocycles, :user_id, unique: true, where: "ended_on IS NULL",
      name: "index_mesocycles_on_active_user"
    add_check_constraint :mesocycles, "weeks > 0 AND weeks <= 16", name: "mesocycles_weeks_check"
    add_check_constraint :mesocycles, "deload_week IS NULL OR (deload_week > 0 AND deload_week <= weeks)",
      name: "mesocycles_deload_week_check"
    add_check_constraint :mesocycles, "ended_on IS NULL OR ended_on >= started_on", name: "mesocycles_dates_check"
  end
end
