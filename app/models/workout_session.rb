class WorkoutSession < ApplicationRecord
  belongs_to :user
  belongs_to :workout_template, optional: true
  has_many :set_entries, dependent: :destroy

  accepts_nested_attributes_for :set_entries, reject_if: :blank_working_set?, allow_destroy: true

  validates :performed_at, presence: true
  validates :session_rpe, numericality: { in: 0..10 }, allow_nil: true

  # The order the session reads in, everywhere it is displayed.
  #
  # `set_index` restarts at 1 for each exercise, so sorting the whole session by
  # it interleaves them: two exercises of two sets came back as bench 1, squat 1,
  # bench 2, squat 2 — a shuffle of the workout that was actually performed. The
  # session has no column recording the order its sets were logged in, but it
  # does not need one: rows are inserted in the order the form submitted them, so
  # the id order is that order, and the first id per exercise is where that
  # exercise belongs.
  def ordered_set_entries
    entries = set_entries.to_a
    first_logged = {}
    entries.sort_by { |entry| entry.id || Float::INFINITY }.each_with_index do |entry, position|
      first_logged[entry.exercise_id] ||= position
    end

    entries.sort_by { |entry| [ first_logged[entry.exercise_id] || 0, entry.set_index.to_i ] }
  end

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
