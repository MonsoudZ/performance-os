class CreateGoalPeriods < ActiveRecord::Migration[8.1]
  GOAL_TYPES = %w[
    build_muscle
    lose_fat
    increase_strength
    athletic_performance
    vertical_jump
    marathon
    longevity
  ].freeze

  def change
    create_table :goal_periods do |table|
      table.references :user, null: false, foreign_key: true
      table.string :goal_type, null: false
      table.jsonb :params, null: false, default: {}
      table.date :started_on, null: false
      table.date :ended_on

      table.timestamps
    end

    add_index :goal_periods, :user_id,
      unique: true,
      where: "ended_on IS NULL",
      name: "index_goal_periods_on_active_user"
    add_check_constraint :goal_periods,
      "goal_type IN (#{GOAL_TYPES.map { |type| "'#{type}'" }.join(", ")})",
      name: "goal_periods_goal_type_check"
    add_check_constraint :goal_periods,
      "ended_on IS NULL OR ended_on >= started_on",
      name: "goal_periods_dates_check"
  end
end
