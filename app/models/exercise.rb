class Exercise < ApplicationRecord
  MODALITIES = %w[barbell dumbbell machine bodyweight cable other].freeze

  belongs_to :user, optional: true
  has_many :exercise_muscle_contributions, dependent: :destroy
  has_many :muscle_groups, through: :exercise_muscle_contributions
  has_many :exercise_prescriptions, dependent: :destroy
  has_many :set_entries, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :modality, inclusion: { in: MODALITIES }
  validates :default_unit, inclusion: { in: %w[kg reps seconds meters] }

  scope :available_to, ->(user) { where(user_id: [ nil, user.id ]).order(:name) }
end
