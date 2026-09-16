class CoachingDecision < ApplicationRecord
  # Every kind of conclusion the engine writes. A type outside this list is a
  # decision nothing can find: every lookup goes through `of_type`, so one
  # letter wrong made a recommendation that existed, counted towards nothing and
  # answered no question — the opposite of the traceability the whole table is
  # for. The database enforces the same list, so adding one means a migration.
  DECISION_TYPES = %w[
    daily_readiness
    double_progression
    daily_nutrition
    nutrition_adjustment
    weekly_review
    daily_training
  ].freeze

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
  validates :decision_type, inclusion: { in: DECISION_TYPES }
  validates :confidence, inclusion: { in: %w[low moderate high] }
  validates :retraction_reason, presence: true, if: :retracted_at?

  scope :active_evidence, -> { where(retracted_at: nil) }
  # The complement. Nothing may feed a new decision from here — this exists so
  # the UI can show a user what was withdrawn and why, which is the other half of
  # the promise that a recommendation is traceable.
  scope :withdrawn, -> { where.not(retracted_at: nil) }
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

  # Why the recommendation was withdrawn, in the user's terms rather than the
  # rule's. Falls back to the raw reason so a new one is still readable.
  RETRACTION_EXPLANATIONS = {
    "workout_session_corrected" => "the workout behind it was corrected",
    "workout_session_deleted" => "the workout behind it was deleted"
  }.freeze

  def retraction_explanation
    return if retraction_reason.blank?

    RETRACTION_EXPLANATIONS.fetch(retraction_reason) { retraction_reason.humanize.downcase }
  end
end
