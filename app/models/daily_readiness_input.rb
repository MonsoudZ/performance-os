class DailyReadinessInput < ApplicationRecord
  # The subjective taps the user provides; objective metrics come from the watch.
  SUBJECTIVE_FIELDS = %i[sleep_quality soreness fatigue stress].freeze

  # The sources that mean part of this row was measured rather than typed.
  WATCH_SOURCES = %w[healthkit mixed].freeze

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
    sleep_minutes.present? && source.in?(WATCH_SOURCES)
  end

  # What this row's source is, read off what the row actually holds.
  #
  # "manual" is a row nothing measured, "healthkit" a row nobody has answered,
  # "mixed" a row holding both — and which kind of evidence arrived first never
  # changes which of the three it is.
  #
  # Every writer asks this rather than deciding for itself, because three of
  # them used to and all three disagreed. The materializer had it right. The
  # check-in controllers read only the objective metrics, so answering a
  # watch-synced night demoted it to "manual" and the dashboard stopped saying
  # where the sleep figure it was still showing had come from. The edit screen
  # never set it at all, so answering that same night from /readiness_inputs
  # left it reading "healthkit" while `checked_in?` said it was answered.
  #
  # `measured:` is for a writer that knows it is bringing watch data with it:
  # sleep the watch measured looks identical to sleep somebody typed, so the
  # row cannot work that out on its own and the materializer has to say so.
  def derived_source(measured: watch_evidence?)
    return "manual" unless measured

    answered_any? ? "mixed" : "healthkit"
  end

  def watch_evidence?
    source.in?(WATCH_SOURCES) || hrv_sdnn_ms.present? || resting_hr.present?
  end

  def answered_any?
    SUBJECTIVE_FIELDS.any? { |field| public_send(field).present? }
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
