class MuscleGroup < ApplicationRecord
  has_many :exercise_muscle_contributions, dependent: :destroy
  has_many :exercises, through: :exercise_muscle_contributions

  validates :name, presence: true, uniqueness: true
end
