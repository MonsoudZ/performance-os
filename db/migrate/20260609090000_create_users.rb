class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |table|
      table.string :email, null: false
      table.date :birth_date
      table.string :sex
      table.decimal :height_cm, precision: 5, scale: 1
      table.string :unit_system, null: false, default: "metric"

      table.timestamps
    end

    add_index :users, :email, unique: true
    add_check_constraint :users, "sex IN ('male', 'female', 'unspecified')", name: "users_sex_check"
    add_check_constraint :users, "unit_system IN ('metric', 'imperial')", name: "users_unit_system_check"
  end
end
