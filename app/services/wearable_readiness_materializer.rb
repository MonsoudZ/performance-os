# Folds a day's objective samples into that day's readiness check-in and scores
# it. The rest of the plan is recomputed by the caller, once, after every
# materializer for the day has run.
class WearableReadinessMaterializer
  # The metrics this materializer is built out of. A day that synced only steps
  # or a weigh-in has nothing to say about readiness, and inventing a blank
  # check-in for it would put an unanswered day on the record as an answered one.
  READINESS_METRICS = %w[hrv_sdnn_ms resting_hr_bpm sleep_asleep].freeze

  def initialize(user, metric_date:)
    @user = user
    @metric_date = metric_date
  end

  def call
    readiness_input = user.daily_readiness_inputs.find_by(metric_date: metric_date)
    return if readiness_input.nil? && READINESS_METRICS.none? { |metric| samples(metric).exists? }

    readiness_input ||= user.daily_readiness_inputs.new(metric_date: metric_date)
    readiness_input.assign_attributes(
      hrv_sdnn_ms: median_value("hrv_sdnn_ms"),
      resting_hr: median_value("resting_hr_bpm")&.round,
      sleep_minutes: sleep_minutes
    )
    # This write is watch data by construction — a night the watch measured is
    # indistinguishable from one somebody typed once it is in the column — so it
    # says so rather than leaving the row to guess.
    readiness_input.source = readiness_input.derived_source(measured: true)
    readiness_input.save!

    score, decision = ReadinessEvaluator.new(readiness_input).call

    [ readiness_input, score, decision ]
  end

  private

  attr_reader :user, :metric_date

  def samples(metric_type)
    relation = user.wearable_samples.of_metric(metric_type)
    if WearableSample.end_dated?(metric_type)
      relation.where(ended_at: user.local_day_range(metric_date))
    else
      relation.where(started_at: user.local_day_range(metric_date))
    end
  end

  def median_value(metric_type)
    values = samples(metric_type).where.not(value: nil).pluck(:value).map(&:to_f).sort
    return if values.empty?

    midpoint = values.length / 2
    values.length.odd? ? values[midpoint] : (values[midpoint - 1] + values[midpoint]) / 2
  end

  def sleep_minutes
    total = samples("sleep_asleep").sum(:value)
    total.positive? ? total.round : nil
  end
end
