# Turns a day's synced body-mass samples into the weigh-in the rest of the app
# already understands, so a user with a connected scale gets a weight trend, an
# adaptive expenditure estimate and calorie targets without logging anything.
class WearableBodyMassMaterializer
  SOURCE = "healthkit".freeze

  def initialize(user, metric_date:)
    @user = user
    @metric_date = metric_date
  end

  def call
    weight_kg = median_weight_kg
    return if weight_kg.nil?

    # Derived from the samples rather than owned by the user, so a later sync
    # that adds readings for the same day re-derives the figure. Manual weigh-ins
    # are a separate row and are never touched.
    body_metric = user.body_metrics.find_or_initialize_by(measured_on: metric_date, source: SOURCE)
    body_metric.update!(weight_kg: weight_kg)
    body_metric
  end

  private

  attr_reader :user, :metric_date

  # Median, not mean: stepping off a scale early records a plausible-looking
  # fraction of a bodyweight, and one of those would drag an average far enough
  # to move a calorie target.
  def median_weight_kg
    values = user.wearable_samples
      .of_metric("body_mass_kg")
      .where(started_at: user.local_day_range(metric_date))
      .where.not(value: nil)
      .pluck(:value)
      .map { |value| Units.decimal(value) }
      .sort
    return if values.empty?

    midpoint = values.length / 2
    return values[midpoint] if values.length.odd?

    ((values[midpoint - 1] + values[midpoint]) / 2).round(Units::WEIGHT_SCALE)
  end
end
