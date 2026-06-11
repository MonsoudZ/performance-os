class CoachNarrative < ApplicationRecord
  STATUSES = %w[pending complete failed].freeze
  MAX_QUESTION_LENGTH = 280

  # The canned prompts surfaced as one-tap questions. They mirror the things the
  # decision DAG can actually answer, so the model is never asked to speculate
  # beyond the grounded data.
  SUGGESTED_QUESTIONS = [
    "Why am I being told to train this way today?",
    "Why is my calorie target where it is?",
    "What does my conditioning directive mean for today?",
    "How did my check-in change today's plan?"
  ].freeze

  belongs_to :user
  belongs_to :coaching_decision, optional: true

  validates :question, presence: true, length: { maximum: MAX_QUESTION_LENGTH }
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  def pending?  = status == "pending"
  def complete? = status == "complete"
  def failed?   = status == "failed"
end
