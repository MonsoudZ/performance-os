class Exercise < ApplicationRecord
  MODALITIES = %w[barbell dumbbell machine bodyweight cable other].freeze

  belongs_to :user, optional: true
  # delete_all, not destroy: a contribution row has no primary key, so
  # instantiating one to destroy it builds `WHERE "" IS NULL` and raises. It also
  # has no callbacks worth running. See ExerciseMuscleContribution.
  has_many :exercise_muscle_contributions, dependent: :delete_all
  has_many :muscle_groups, through: :exercise_muscle_contributions
  has_many :exercise_prescriptions, dependent: :destroy
  has_many :set_entries, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :modality, inclusion: { in: MODALITIES }
  validates :default_unit, inclusion: { in: %w[kg reps seconds meters] }

  scope :available_to, ->(user) { where(user_id: [ nil, user.id ]).order(:name) }
end
