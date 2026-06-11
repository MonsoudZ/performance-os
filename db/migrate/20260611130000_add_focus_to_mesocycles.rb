class AddFocusToMesocycles < ActiveRecord::Migration[8.1]
  def change
    add_column :mesocycles, :focus, :string, null: false, default: "hypertrophy"
    add_check_constraint :mesocycles, "focus IN ('hypertrophy', 'strength', 'power')",
      name: "mesocycles_focus_check"
  end
end
