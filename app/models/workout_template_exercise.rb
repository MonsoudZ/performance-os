class WorkoutTemplateExercise < ApplicationRecord
  belongs_to :workout_template, inverse_of: :workout_template_exercises
  belongs_to :exercise

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :exercise_id, uniqueness: { scope: :workout_template_id }
  validate :exercise_available_to_user

  private

  def exercise_available_to_user
    return if workout_template.blank? || exercise.blank?
    return if exercise.user_id.nil? || exercise.user_id == workout_template.user_id

    errors.add(:exercise, "is not available to this user")
  end
end
