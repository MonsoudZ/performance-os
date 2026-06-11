class MuscleGroup < ApplicationRecord
  # Weekly hard-set volume landmarks (fractional sets/week), RP-style guidance:
  # MEV = minimum effective, MAV = adaptive target, MRV = maximum recoverable.
  LANDMARKS = {
    "chest" => { mev: 8, mav: 16, mrv: 22 },
    "back" => { mev: 10, mav: 18, mrv: 25 },
    "shoulders" => { mev: 8, mav: 18, mrv: 26 },
    "biceps" => { mev: 8, mav: 16, mrv: 26 },
    "triceps" => { mev: 6, mav: 12, mrv: 18 },
    "quads" => { mev: 8, mav: 16, mrv: 20 },
    "hamstrings" => { mev: 6, mav: 12, mrv: 20 },
    "glutes" => { mev: 4, mav: 12, mrv: 16 },
    "calves" => { mev: 8, mav: 14, mrv: 20 },
    "abs" => { mev: 6, mav: 16, mrv: 25 }
  }.freeze

  has_many :exercise_muscle_contributions, dependent: :destroy
  has_many :exercises, through: :exercise_muscle_contributions

  validates :name, presence: true, uniqueness: true

  def landmark
    LANDMARKS[name]
  end
end
