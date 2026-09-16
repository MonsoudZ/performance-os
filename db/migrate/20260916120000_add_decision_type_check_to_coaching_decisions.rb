class AddDecisionTypeCheckToCoachingDecisions < ActiveRecord::Migration[8.1]
  # The link roles were constrained and the decision types were not, though the
  # conventions here say both should be. A type outside the list is a decision
  # every `of_type` lookup misses, so it exists without answering anything.
  def change
    add_check_constraint :coaching_decisions,
      "decision_type IN ('daily_readiness', 'double_progression', 'daily_nutrition', " \
      "'nutrition_adjustment', 'weekly_review', 'daily_training')",
      name: "coaching_decisions_decision_type_check"
  end
end
