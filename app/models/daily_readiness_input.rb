class DailyReadinessInput < ApplicationRecord
  # The subjective taps the user provides; objective metrics come from the watch.
  SUBJECTIVE_FIELDS = %i[sleep_quality soreness fatigue stress].freeze

  belongs_to :user

  validates :metric_date, presence: true, uniqueness: { scope: :user_id }
  validates :sleep_quality, :soreness, :fatigue, :stress,
    inclusion: { in: 1..5 },
    allow_nil: true
  validates :sleep_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :resting_hr, numericality: { greater_than: 0 }, allow_nil: true
  validates :hrv_sdnn_ms, numericality: { greater_than: 0 }, allow_nil: true
  validates :source, inclusion: { in: %w[manual healthkit mixed] }

  # The day's check-in is done once the subjective taps are in; objective metrics
  # alone (a watch sync) don't count.
  def checked_in?
    SUBJECTIVE_FIELDS.all? { |field| public_send(field).present? }
  end

  def sleep_from_watch?
    sleep_minutes.present? && source.in?(%w[healthkit mixed])
  end

  # Sleep is stored in minutes but entered in hours, the same store-canonical /
  # enter-friendly split used for body weight.
  def sleep_hours
    return if sleep_minutes.nil?

    (sleep_minutes / 60.0).round(2)
  end

  def sleep_hours=(value)
    self.sleep_minutes = value.present? ? (value.to_f * 60).round : nil
  end
end
