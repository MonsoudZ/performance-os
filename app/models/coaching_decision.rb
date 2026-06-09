class CoachingDecision < ApplicationRecord
  belongs_to :user
  has_many :child_links,
    class_name: "CoachingDecisionLink",
    foreign_key: :parent_decision_id,
    dependent: :destroy,
    inverse_of: :parent_decision
  has_many :child_decisions, through: :child_links, source: :child_decision
  has_many :parent_links,
    class_name: "CoachingDecisionLink",
    foreign_key: :child_decision_id,
    dependent: :restrict_with_exception,
    inverse_of: :child_decision
  has_many :parent_decisions, through: :parent_links, source: :parent_decision

  validates :decision_type, :rule_key, :rule_version, presence: true
  validates :confidence, inclusion: { in: %w[low moderate high] }
end
