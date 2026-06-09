class CreateReadinessTables < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_readiness_inputs do |table|
      table.references :user, null: false, foreign_key: true
      table.date :metric_date, null: false
      table.decimal :hrv_sdnn_ms, precision: 6, scale: 2
      table.integer :resting_hr
      table.integer :sleep_minutes
      table.integer :sleep_quality
      table.integer :soreness
      table.integer :fatigue
      table.integer :stress
      table.string :source, null: false, default: "manual"

      table.timestamps
    end

    add_index :daily_readiness_inputs, [ :user_id, :metric_date ], unique: true

    %i[sleep_quality soreness fatigue stress].each do |column|
      add_check_constraint :daily_readiness_inputs,
        "#{column} BETWEEN 1 AND 5",
        name: "readiness_inputs_#{column}_check"
    end

    create_table :readiness_scores, id: false do |table|
      table.references :user, null: false, foreign_key: true
      table.date :score_date, null: false
      table.integer :score, null: false
      table.jsonb :components, null: false, default: {}

      table.timestamps
    end

    add_index :readiness_scores, [ :user_id, :score_date ], unique: true
    add_check_constraint :readiness_scores, "score BETWEEN 0 AND 100", name: "readiness_scores_score_check"
  end
end
