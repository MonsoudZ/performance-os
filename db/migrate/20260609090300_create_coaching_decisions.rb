class CreateCoachingDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :coaching_decisions do |table|
      table.references :user, null: false, foreign_key: true
      table.string :decision_type, null: false
      table.string :rule_key, null: false
      table.string :rule_version, null: false
      table.jsonb :inputs, null: false
      table.jsonb :output, null: false
      table.jsonb :citations, null: false, default: []
      table.string :confidence

      table.timestamps
    end

    add_index :coaching_decisions, [ :user_id, :decision_type, :created_at ],
      name: "index_decisions_on_user_type_and_created_at"
    add_check_constraint :coaching_decisions,
      "confidence IN ('low', 'moderate', 'high')",
      name: "coaching_decisions_confidence_check"
  end
end
