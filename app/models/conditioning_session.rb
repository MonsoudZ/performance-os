class ConditioningSession < ApplicationRecord
  # Distance-based types derive a pace; the others (jumps, plyometrics) don't.
  ACTIVITY_TYPES = %w[run bike row swim walk jump plyometric other].freeze
  DISTANCE_BASED = %w[run bike row swim walk].freeze
  # 5-zone model as a fraction of max HR; Zone 2 (the endurance/longevity base)
  # is 60–70%.
  ZONE_CEILINGS = { "Z1" => 0.60, "Z2" => 0.70, "Z3" => 0.80, "Z4" => 0.90, "Z5" => 1.01 }.freeze

  belongs_to :user

  validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
  validates :performed_at, presence: true
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :distance_meters, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :avg_hr_bpm, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :performed_between, ->(range) { where(performed_at: range) }

  # Enter-friendly accessors over the canonical seconds/meters columns.
  def duration_minutes
    return if duration_seconds.nil?

    (duration_seconds / 60.0).round(2)
  end

  def duration_minutes=(value)
    self.duration_seconds = value.present? ? (value.to_f * 60).round : nil
  end

  def distance_km
    return if distance_meters.nil?

    (distance_meters / 1000.0).round(2)
  end

  def distance_km=(value)
    self.distance_meters = value.present? ? (value.to_f * 1000).round : nil
  end

  def distance_based?
    DISTANCE_BASED.include?(activity_type)
  end

  # Seconds per kilometre, or nil when there's no usable distance.
  def pace_seconds_per_km
    return unless distance_based? && distance_meters.to_i.positive?

    (duration_seconds / (distance_meters / 1000.0)).round
  end

  # 5-zone classification from average HR against the user's max HR.
  def hr_zone(max_hr = user&.max_hr)
    return if avg_hr_bpm.blank? || max_hr.blank? || max_hr.zero?

    fraction = avg_hr_bpm.to_f / max_hr
    ZONE_CEILINGS.find { |_zone, ceiling| fraction < ceiling }&.first || "Z5"
  end
end
