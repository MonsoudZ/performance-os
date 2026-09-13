class WearableSyncIngestor
  MAX_BATCH_SIZE = 1_000

  def initialize(device, samples:)
    @device = device
    @samples = samples
  end

  def call
    raise ArgumentError, "batch exceeds #{MAX_BATCH_SIZE} samples" if samples.size > MAX_BATCH_SIZE

    affected_dates = Set.new
    inserted = 0
    refreshed = 0

    ApplicationRecord.transaction do
      samples.each do |attributes|
        sample = device.wearable_samples.find_or_initialize_by(external_id: attributes.fetch("external_id"))
        new_record = sample.new_record?
        next unless new_record || refreshable?(sample, attributes)

        sample.assign_attributes(normalized_attributes(attributes))
        sample.user = device.user
        next unless new_record || sample.changed?

        sample.save!
        new_record ? inserted += 1 : refreshed += 1
        affected_dates << device.user.local_date_at(sample.dated_at)
      end
      device.update!(last_synced_at: Time.current)
    end

    # Defer the evaluator pipeline so the device's request returns immediately;
    # the dashboard fills in over the stream once each date is materialized.
    affected_dates.sort.each do |metric_date|
      WearableDayMaterializeJob.perform_later(device.user, metric_date)
    end

    {
      inserted: inserted,
      refreshed: refreshed,
      duplicates: samples.size - inserted - refreshed,
      materialized_dates: affected_dates.sort
    }
  end

  private

  attr_reader :device, :samples

  # Replaying a batch is safe because a HealthKit UUID names one immutable
  # sample. Daily totals are the exception — they are keyed by date and were
  # still accruing when they were first sent — so those, and only those, are
  # allowed to be corrected in place. The stored metric type decides, not the
  # claimed one, so a replay cannot turn a night of sleep into a step count.
  def refreshable?(sample, attributes)
    WearableSample.daily_total?(sample.metric_type) &&
      sample.metric_type == attributes["metric_type"]
  end

  def normalized_attributes(attributes)
    metric_type = attributes.fetch("metric_type")
    {
      metric_type: metric_type,
      started_at: Time.iso8601(attributes.fetch("started_at")),
      ended_at: attributes["ended_at"].present? ? Time.iso8601(attributes["ended_at"]) : nil,
      value: normalized_value(metric_type, attributes),
      # An unknown metric type has no canonical unit, so leave it blank and let
      # the model's inclusion validation reject the sample by name.
      unit: WearableSample::METRIC_UNITS[metric_type],
      metadata: attributes.fetch("metadata", {})
    }
  end

  # Sleep segments and workouts are intervals, so their value is recoverable from
  # the timestamps. Devices that send it anyway are believed — a workout's own
  # elapsed time excludes pauses that the start-to-end span does not.
  def normalized_value(metric_type, attributes)
    return attributes["value"] unless WearableSample.duration_metric?(metric_type)
    return attributes["value"] if attributes["value"].present?

    seconds = Time.iso8601(attributes.fetch("ended_at")) - Time.iso8601(attributes.fetch("started_at"))
    case WearableSample::DURATION_METRICS.fetch(metric_type)
    when :minutes then (seconds / 60).round(3)
    when :seconds then seconds.round
    end
  end
end
