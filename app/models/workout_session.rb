class WorkoutSession < ApplicationRecord
  belongs_to :user
  belongs_to :workout_template, optional: true
  has_many :set_entries, dependent: :destroy

  accepts_nested_attributes_for :set_entries, reject_if: :blank_working_set?

  validates :performed_at, presence: true
  validates :session_rpe, numericality: { in: 0..10 }, allow_nil: true

  def template_name
    template_snapshot["name"]
  end

  def planned_working_sets
    template_snapshot.fetch("exercises", []).sum { |exercise| exercise.fetch("working_sets", 0).to_i }
  end

  def completed_working_sets
    set_entries.count { |entry| !entry.is_warmup? && entry.reps.present? }
  end

  def completion_percentage
    return 100 if planned_working_sets.zero?

    [ (completed_working_sets.fdiv(planned_working_sets) * 100).round, 100 ].min
  end

  private

  def blank_working_set?(attributes)
    attributes.values_at("weight_kg", "reps", "rir").all?(&:blank?)
  end
end
