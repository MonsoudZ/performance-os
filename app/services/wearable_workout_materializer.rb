# Turns synced workouts into ConditioningSession rows, so a run recorded on a
# watch counts towards the weekly conditioning target the same way a logged one
# does.
class WearableWorkoutMaterializer
  def initialize(user, metric_date:)
    @user = user
    @metric_date = metric_date
  end

  def call
    samples.filter_map { |sample| import(sample) }
  end

  private

  attr_reader :user, :metric_date

  def samples
    user.wearable_samples
      .of_metric("workout")
      .where(started_at: user.local_day_range(metric_date))
      .order(:started_at)
  end

  # Created once and then left alone. Samples are immutable, so re-materializing
  # a day would only ever rewrite a session with the values it already has —
  # while happily discarding anything the user corrected by hand afterwards.
  def import(sample)
    return if user.conditioning_sessions.exists?(wearable_sample_id: sample.id)

    duration_seconds = sample.value.to_i
    return unless duration_seconds.positive?

    user.conditioning_sessions.create!(
      wearable_sample: sample,
      performed_at: sample.started_at,
      activity_type: activity_type(sample),
      duration_seconds: duration_seconds,
      distance_meters: metadata_integer(sample, "distance_meters"),
      avg_hr_bpm: metadata_integer(sample, "avg_hr_bpm")
    )
  end

  # The device maps its own workout taxonomy into this app's vocabulary before
  # syncing, because that enum lives on the device. Anything unrecognized is
  # still a session worth counting, so it lands as "other" rather than being
  # dropped.
  def activity_type(sample)
    claimed = sample.metadata["activity_type"].to_s
    ConditioningSession::ACTIVITY_TYPES.include?(claimed) ? claimed : "other"
  end

  def metadata_integer(sample, key)
    value = sample.metadata[key]
    return if value.blank?

    integer = Integer(value, exception: false) || Float(value, exception: false)&.round
    integer if integer&.positive?
  end
end
