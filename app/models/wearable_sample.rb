class WearableSample < ApplicationRecord
  METRIC_UNITS = {
    "hrv_sdnn_ms" => "ms",
    "resting_hr_bpm" => "bpm",
    "sleep_asleep" => "minutes"
  }.freeze

  belongs_to :user
  belongs_to :wearable_device

  validates :external_id, :started_at, presence: true
  validates :external_id, uniqueness: { scope: :wearable_device_id }
  validates :metric_type, inclusion: { in: METRIC_UNITS.keys }
  validates :unit, inclusion: { in: METRIC_UNITS.values }
  validates :value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :canonical_unit
  validate :same_user_as_device

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
