class User < ApplicationRecord
  EXPERIENCE_LEVELS = %w[beginner intermediate advanced].freeze
  EQUIPMENT_OPTIONS = Exercise::MODALITIES

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :goal_periods, dependent: :destroy
  has_many :daily_readiness_inputs, dependent: :destroy
  has_many :readiness_scores, dependent: :destroy
  has_many :coaching_decisions, dependent: :destroy
  has_many :exercises, dependent: :destroy
  has_many :exercise_prescriptions, dependent: :destroy
  has_many :workout_templates, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy
  has_many :foods, dependent: :destroy
  has_many :food_log_entries, dependent: :destroy
  has_many :body_metrics, dependent: :destroy
  has_many :weight_trends, dependent: :destroy
  has_many :expenditure_estimates, dependent: :destroy
  has_many :wearable_devices, dependent: :destroy
  has_many :wearable_samples, dependent: :destroy
  has_many :conditioning_sessions, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :mesocycles, dependent: :destroy
  has_many :coach_narratives, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :unit_system, inclusion: { in: %w[metric imperial] }
  validates :experience_level, inclusion: { in: EXPERIENCE_LEVELS }
  validates :training_days_per_week,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 7 }
  validates :available_equipment, presence: true
  validate :recognized_time_zone
  validate :recognized_equipment

  before_validation :normalize_equipment

  def active_goal
    goal_periods.active_on(local_date).order(started_on: :desc).first
  end

  def local_time
    Time.current.in_time_zone(time_zone)
  end

  def local_date
    Time.current.in_time_zone(time_zone).to_date
  end

  def local_date_at(time)
    time.in_time_zone(time_zone).to_date
  end

  def local_day_range(date)
    zone = ActiveSupport::TimeZone[time_zone]
    zone.local(date.year, date.month, date.day).all_day
  end

  private

  def normalize_equipment
    return if available_equipment.nil?

    self.available_equipment = available_equipment.compact_blank.uniq
  end

  def recognized_time_zone
    errors.add(:time_zone, "is not recognized") unless ActiveSupport::TimeZone[time_zone]
  end

  def recognized_equipment
    return if available_equipment.blank?

    unknown = available_equipment - EQUIPMENT_OPTIONS
    errors.add(:available_equipment, "includes an unknown option") if unknown.any?
  end
end
