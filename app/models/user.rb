class User < ApplicationRecord
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

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :unit_system, inclusion: { in: %w[metric imperial] }
  validate :recognized_time_zone

  def active_goal
    goal_periods.find_by(ended_on: nil)
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

  def recognized_time_zone
    errors.add(:time_zone, "is not recognized") unless ActiveSupport::TimeZone[time_zone]
  end
end
