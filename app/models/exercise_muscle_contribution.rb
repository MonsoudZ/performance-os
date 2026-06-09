class ExerciseMuscleContribution < ApplicationRecord
  belongs_to :exercise
  belongs_to :muscle_group

  validates :role, inclusion: { in: %w[primary secondary] }
  validates :fraction, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
end
