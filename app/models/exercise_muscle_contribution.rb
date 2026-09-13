# One row per exercise/muscle pair, carrying how much of a set on that exercise
# counts towards that muscle. The (exercise_id, muscle_group_id) unique index is
# what stops a muscle being double-counted in weekly volume.
class ExerciseMuscleContribution < ApplicationRecord
  belongs_to :exercise
  belongs_to :muscle_group

  validates :role, inclusion: { in: %w[primary secondary] }
  validates :fraction, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
end
