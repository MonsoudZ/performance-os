class CreateConditioningSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :max_hr, :integer

    create_table :conditioning_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :activity_type, null: false
      t.datetime :performed_at, null: false
      t.integer :duration_seconds, null: false
      t.integer :distance_meters
      t.integer :avg_hr_bpm
      t.text :notes
      t.timestamps
    end

    add_index :conditioning_sessions, %i[user_id performed_at]
    add_check_constraint :conditioning_sessions, "duration_seconds > 0", name: "conditioning_duration_check"
    add_check_constraint :conditioning_sessions, "distance_meters IS NULL OR distance_meters >= 0", name: "conditioning_distance_check"
    add_check_constraint :conditioning_sessions, "avg_hr_bpm IS NULL OR avg_hr_bpm > 0", name: "conditioning_hr_check"
    add_check_constraint :users, "max_hr IS NULL OR max_hr > 0", name: "users_max_hr_check"
  end
end
