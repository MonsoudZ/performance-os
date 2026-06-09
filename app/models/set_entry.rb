class SetEntry < ApplicationRecord
  belongs_to :workout_session
  belongs_to :exercise

  validates :set_index, numericality: { only_integer: true, greater_than: 0 }
  validates :reps, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :weight_kg, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :rir, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :rpe, numericality: { in: 0..10 }, allow_nil: true
  validate :exercise_available_to_workout_user

  private

  def exercise_available_to_workout_user
    return if workout_session.blank? || exercise.blank?
    return if exercise.user_id.nil? || exercise.user_id == workout_session.user_id

    errors.add(:exercise, "is not available to this user")
  end
end
