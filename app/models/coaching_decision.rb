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
  validates :retraction_reason, presence: true, if: :retracted_at?

  scope :active_evidence, -> { where(retracted_at: nil) }
  scope :of_type, ->(decision_type) { where(decision_type:) }
  scope :latest_first, -> { order(created_at: :desc) }

  # Match a top-level JSON input key, e.g. for_input("plan_date", date).
  # Values are compared as text, matching how the inputs are serialized.
  scope :for_input, ->(key, value) { where("inputs ->> ? = ?", key.to_s, value.to_s) }

  # Match the prescription snapshot id nested in a progression decision's inputs.
  scope :for_prescription, ->(prescription_id) { where("inputs #>> '{prescription,id}' = ?", prescription_id.to_s) }

  def retract!(reason:)
    update!(retracted_at: Time.current, retraction_reason: reason) unless retracted_at?
  end
end
