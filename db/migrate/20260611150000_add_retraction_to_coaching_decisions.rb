class AddRetractionToCoachingDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :coaching_decisions, :retracted_at, :datetime
    add_column :coaching_decisions, :retraction_reason, :string
    add_index :coaching_decisions, :retracted_at

    add_check_constraint :coaching_decisions,
      "(retracted_at IS NULL AND retraction_reason IS NULL) OR (retracted_at IS NOT NULL AND retraction_reason IS NOT NULL)",
      name: "coaching_decisions_retraction_check"
  end
end
