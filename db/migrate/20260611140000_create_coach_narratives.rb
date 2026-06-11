class CreateCoachNarratives < ActiveRecord::Migration[8.1]
  def change
    create_table :coach_narratives do |t|
      t.references :user, null: false, foreign_key: true
      # The daily_training decision the question was grounded on. Nullified
      # rather than cascaded so a narrative survives a plan regeneration as an
      # audit record of what was asked and answered.
      t.references :coaching_decision, null: true, foreign_key: { on_delete: :nullify }

      t.string  :question, null: false
      t.text    :answer
      t.string  :status, null: false, default: "pending"
      t.string  :model_id
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens

      t.timestamps
    end

    add_index :coach_narratives, [ :user_id, :created_at ]
    add_check_constraint :coach_narratives,
      "status IN ('pending', 'complete', 'failed')",
      name: "coach_narratives_status_check"
  end
end
