class AddNutritionDecisionLinkRole < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :coaching_decision_links, name: "coaching_decision_links_role_check"
    add_check_constraint :coaching_decision_links,
      "role IN ('readiness', 'progression', 'nutrition')",
      name: "coaching_decision_links_role_check"
  end
end
