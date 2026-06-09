class WorkoutSession < ApplicationRecord
  belongs_to :user
  has_many :set_entries, dependent: :destroy

  accepts_nested_attributes_for :set_entries, reject_if: :blank_working_set?

  validates :performed_at, presence: true
  validates :session_rpe, numericality: { in: 0..10 }, allow_nil: true

  private

  def blank_working_set?(attributes)
    attributes.values_at("weight_kg", "reps", "rir").all?(&:blank?)
  end
end
