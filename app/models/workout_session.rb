class WorkoutSession < ApplicationRecord
  belongs_to :user
  belongs_to :workout_template, optional: true
  has_many :set_entries, dependent: :destroy

  accepts_nested_attributes_for :set_entries, reject_if: :blank_working_set?, allow_destroy: true

  validates :performed_at, presence: true
  validates :session_rpe, numericality: { in: 0..10 }, allow_nil: true
  validate :workout_template_belongs_to_user

  # Link this session to the workout it was run from, and freeze what that
  # workout was asking for on the day it was logged.
  #
  # The snapshot is the point rather than the link: a later block change must not
  # be able to rewrite what a logged session was asked to do, which is the same
  # promise the whole decision trail rests on. This lived in a controller private
  # method, so a session logged from the phone set the foreign key and stored an
  # empty snapshot — no planned set count, no name, and `template_name` null in
  # the API's own response.
  def attach_template(template)
    return if template.blank? || performed_at.blank?

    self.workout_template = template
    self.template_snapshot = WorkoutTemplateSnapshot.new(
      template, log_date: user.local_date_at(performed_at)
    ).call
  end

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

  # The web looked its template up through `Current.user.workout_templates`, so
  # a foreign id simply came back nil; the API permitted `workout_template_id`
  # straight through and stored it. A session pointing into another account's
  # data is not this account's to hold, whichever writer sets it.
  def workout_template_belongs_to_user
    return if workout_template.blank? || workout_template.user_id == user_id

    errors.add(:workout_template, "is not available to this user")
  end

  def blank_working_set?(attributes)
    attributes.values_at("weight_kg", "reps", "rir").all?(&:blank?)
  end
end
