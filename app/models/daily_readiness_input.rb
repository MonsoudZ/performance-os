class DailyReadinessInput < ApplicationRecord
  belongs_to :user

  validates :metric_date, presence: true, uniqueness: { scope: :user_id }
  validates :sleep_quality, :soreness, :fatigue, :stress,
    inclusion: { in: 1..5 },
    allow_nil: true
  validates :sleep_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :resting_hr, numericality: { greater_than: 0 }, allow_nil: true
  validates :hrv_sdnn_ms, numericality: { greater_than: 0 }, allow_nil: true
  validates :source, inclusion: { in: %w[manual healthkit mixed] }
end
