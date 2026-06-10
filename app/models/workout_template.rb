class WorkoutTemplate < ApplicationRecord
  WEEKDAYS = Date::DAYNAMES.each_with_index.to_h.freeze

  belongs_to :user
  has_many :workout_template_exercises, -> { order(:position) }, dependent: :destroy, inverse_of: :workout_template
  has_many :exercises, through: :workout_template_exercises
  has_many :workout_sessions, dependent: :nullify

  accepts_nested_attributes_for :workout_template_exercises, allow_destroy: true, reject_if: :all_blank

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validate :valid_weekdays
  validate :has_exercises

  scope :scheduled_on, ->(date) { where("? = ANY(weekdays)", date.wday) }

  def scheduled_on?(date)
    weekdays.include?(date.wday)
  end

  def schedule_label
    return "Unscheduled" if weekdays.empty?

    weekdays.sort.map { |weekday| Date::ABBR_DAYNAMES.fetch(weekday) }.join(" · ")
  end

  private

  def valid_weekdays
    errors.add(:weekdays, "contains an invalid day") unless weekdays.all? { |weekday| weekday.in?(0..6) }
  end

  def has_exercises
    active_items = workout_template_exercises.reject(&:marked_for_destruction?)
    errors.add(:workout_template_exercises, "must include at least one exercise") if active_items.empty?
  end
end
