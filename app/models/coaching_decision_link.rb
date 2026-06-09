class CoachingDecisionLink < ApplicationRecord
  belongs_to :parent_decision, class_name: "CoachingDecision", inverse_of: :child_links
  belongs_to :child_decision, class_name: "CoachingDecision", inverse_of: :parent_links

  validates :role, inclusion: { in: %w[readiness progression nutrition weekly_review] }
  validates :child_decision_id, uniqueness: { scope: :parent_decision_id }
  validate :same_user
  validate :different_decisions

  private

  def same_user
    return if parent_decision.blank? || child_decision.blank?
    return if parent_decision.user_id == child_decision.user_id

    errors.add(:child_decision, "must belong to the same user")
  end

  def different_decisions
    errors.add(:child_decision, "cannot reference itself") if parent_decision_id == child_decision_id
  end
end
