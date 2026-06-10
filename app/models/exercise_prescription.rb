class ExercisePrescription < ApplicationRecord
  # Loading style the progression engine applies. Both are double progression
  # (advance reps, then load); they differ only in which sets gate the increase.
  PROGRESSION_MODELS = {
    "double_progression" => "Straight sets (same load every set)",
    "top_set" => "Top set (heaviest set drives progression)"
  }.freeze

  belongs_to :user
  belongs_to :exercise

  validates :rep_min, :rep_max, :working_sets, numericality: { only_integer: true, greater_than: 0 }
  validates :increment_kg, numericality: { greater_than: 0 }
  validates :target_rir_min, numericality: { greater_than_or_equal_to: 0 }
  validates :target_rir_max, numericality: { greater_than_or_equal_to: 0 }
  validates :progression_model, inclusion: { in: PROGRESSION_MODELS.keys }
  validates :started_on, presence: true
  validate :valid_ranges
  validate :ends_after_start
  validate :exercise_available_to_user

  scope :active, -> { where(ended_on: nil) }
  scope :active_on, ->(date) {
    where("started_on <= ? AND (ended_on IS NULL OR ended_on >= ?)", date, date)
  }
  scope :current, -> { active_on(Date.current) }

  def target_label
    "#{working_sets} × #{rep_min}–#{rep_max} @ #{target_rir_min.to_f.round(1)}–#{target_rir_max.to_f.round(1)} RIR"
  end

  def top_set?
    progression_model == "top_set"
  end

  def progression_model_label
    PROGRESSION_MODELS.fetch(progression_model, progression_model)
  end

  private

  def valid_ranges
    errors.add(:rep_max, "must be at least the minimum") if rep_min && rep_max && rep_max < rep_min
    if target_rir_min && target_rir_max && target_rir_max < target_rir_min
      errors.add(:target_rir_max, "must be at least the minimum")
    end
  end

  def ends_after_start
    return if ended_on.blank? || started_on.blank? || ended_on >= started_on

    errors.add(:ended_on, "must be on or after the start date")
  end

  def exercise_available_to_user
    return if user.blank? || exercise.blank?
    return if exercise.user_id.nil? || exercise.user_id == user_id

    errors.add(:exercise, "is not available to this user")
  end
end
