class WearableSample < ApplicationRecord
  # The canonical unit each metric arrives in. A sample whose unit disagrees is
  # rejected rather than converted: the device is the only thing that knows what
  # it measured, so a mismatch means the payload is wrong, not the scale.
  METRIC_UNITS = {
    "hrv_sdnn_ms" => "ms",
    "resting_hr_bpm" => "bpm",
    "sleep_asleep" => "minutes",
    "workout" => "seconds",
    "step_count" => "count",
    "active_energy_kcal" => "kcal",
    "basal_energy_kcal" => "kcal",
    "body_mass_kg" => "kg"
  }.freeze

  # Metrics whose value is the length of the interval they cover, so the server
  # can derive it when the device leaves `value` blank.
  DURATION_METRICS = {
    "sleep_asleep" => :minutes,
    "workout" => :seconds
  }.freeze

  # A night of sleep belongs to the day it ends on — you wake up into Tuesday
  # having slept through Monday night. Everything else belongs to the day it
  # started.
  END_DATED_METRICS = %w[sleep_asleep].freeze

  # Metrics the device sends as one already-summed row per local day, keyed by
  # date rather than by a HealthKit UUID. Steps and energy accrue all day, so
  # unlike every other metric their value is still moving when it first arrives
  # and a later sync has to be allowed to correct it.
  DAILY_TOTAL_METRICS = %w[step_count active_energy_kcal basal_energy_kcal].freeze

  # `workout` carries the shape of the session in metadata rather than in columns
  # of its own, because no other metric has a shape. The materializer reads these
  # keys and tolerates any of them being absent.
  WORKOUT_METADATA_KEYS = %w[activity_type distance_meters avg_hr_bpm].freeze

  belongs_to :user
  belongs_to :wearable_device

  has_one :conditioning_session, dependent: :nullify

  validates :external_id, :started_at, presence: true
  validates :external_id, uniqueness: { scope: :wearable_device_id }
  validates :metric_type, inclusion: { in: METRIC_UNITS.keys }
  validates :unit, inclusion: { in: METRIC_UNITS.values }
  validates :value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :canonical_unit
  validate :same_user_as_device

  scope :of_metric, ->(metric_type) { where(metric_type: metric_type) }

  def self.duration_metric?(metric_type)
    DURATION_METRICS.key?(metric_type)
  end

  def self.daily_total?(metric_type)
    DAILY_TOTAL_METRICS.include?(metric_type)
  end

  def self.end_dated?(metric_type)
    END_DATED_METRICS.include?(metric_type)
  end

  # The timestamp that decides which local day this sample counts towards.
  def dated_at
    self.class.end_dated?(metric_type) ? ended_at || started_at : started_at
  end

  private

  def canonical_unit
    return if METRIC_UNITS[metric_type] == unit

    errors.add(:unit, "must be canonical for the metric")
  end

  def same_user_as_device
    return if wearable_device.blank? || user_id == wearable_device.user_id

    errors.add(:wearable_device, "must belong to the same user")
  end
end
