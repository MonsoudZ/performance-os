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

    ApplicationRecord.transaction do
      samples.each do |attributes|
        sample = device.wearable_samples.find_or_initialize_by(external_id: attributes.fetch("external_id"))
        next if sample.persisted?

        sample.assign_attributes(normalized_attributes(attributes))
        sample.user = device.user
        sample.save!
        inserted += 1
        affected_dates << metric_date_for(sample)
      end
      device.update!(last_synced_at: Time.current)
    end

    # Defer the evaluator pipeline so the device's request returns immediately;
    # the dashboard fills in over the stream once each date is materialized.
    affected_dates.sort.each do |metric_date|
      WearableReadinessMaterializeJob.perform_later(device.user, metric_date)
    end

    {
      inserted: inserted,
      duplicates: samples.size - inserted,
      materialized_dates: affected_dates.sort
    }
  end

  private

  attr_reader :device, :samples

  def normalized_attributes(attributes)
    metric_type = attributes.fetch("metric_type")
    {
      metric_type: metric_type,
      started_at: Time.iso8601(attributes.fetch("started_at")),
      ended_at: attributes["ended_at"].present? ? Time.iso8601(attributes["ended_at"]) : nil,
      value: normalized_value(metric_type, attributes),
      unit: WearableSample::METRIC_UNITS.fetch(metric_type),
      metadata: attributes.fetch("metadata", {})
    }
  end

  def normalized_value(metric_type, attributes)
    return attributes["value"] unless metric_type == "sleep_asleep"
    return attributes["value"] if attributes["value"].present?

    started_at = Time.iso8601(attributes.fetch("started_at"))
    ended_at = Time.iso8601(attributes.fetch("ended_at"))
    ((ended_at - started_at) / 60).round(3)
  end

  def metric_date_for(sample)
    timestamp = sample.metric_type == "sleep_asleep" ? sample.ended_at || sample.started_at : sample.started_at
    device.user.local_date_at(timestamp)
  end
end
