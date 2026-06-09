class CreateCoachingDecisionLinks < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE coaching_decisions
      SET decision_type = 'daily_readiness',
          inputs = inputs || jsonb_build_object('metric_date', created_at::date::text)
      WHERE rule_key = 'daily_readiness.v1'
        AND decision_type = 'daily_training'
    SQL

    create_table :coaching_decision_links do |table|
      table.references :parent_decision,
        null: false,
        foreign_key: { to_table: :coaching_decisions, on_delete: :cascade }
      table.references :child_decision,
        null: false,
        foreign_key: { to_table: :coaching_decisions, on_delete: :restrict }
      table.string :role, null: false

      table.timestamps
    end

    add_index :coaching_decision_links,
      [ :parent_decision_id, :child_decision_id ],
      unique: true,
      name: "index_coaching_decision_links_unique"
    add_check_constraint :coaching_decision_links,
      "role IN ('readiness', 'progression')",
      name: "coaching_decision_links_role_check"
  end

  def down
    drop_table :coaching_decision_links

    execute <<~SQL
      UPDATE coaching_decisions
      SET decision_type = 'daily_training'
      WHERE rule_key = 'daily_readiness.v1'
        AND decision_type = 'daily_readiness'
    SQL
  end
end
