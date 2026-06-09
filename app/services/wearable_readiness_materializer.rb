class WearableReadinessMaterializer
  def initialize(user, metric_date:)
    @user = user
    @metric_date = metric_date
  end

  def call
    readiness_input = user.daily_readiness_inputs.find_or_initialize_by(metric_date: metric_date)
    readiness_input.assign_attributes(
      hrv_sdnn_ms: median_value("hrv_sdnn_ms"),
      resting_hr: median_value("resting_hr_bpm")&.round,
      sleep_minutes: sleep_minutes,
      source: readiness_source(readiness_input)
    )
    readiness_input.save!

    score, decision = ReadinessEvaluator.new(readiness_input).call
    NutritionEvaluator.new(user, nutrition_date: metric_date).call
    DailyTrainingOrchestrator.new(user, plan_date: metric_date).call if metric_date == user.local_date

    [ readiness_input, score, decision ]
  end

  private

  attr_reader :user, :metric_date

  def samples(metric_type)
    relation = user.wearable_samples.where(metric_type: metric_type)
    if metric_type == "sleep_asleep"
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

  def readiness_source(readiness_input)
    subjective_present = %i[sleep_quality soreness fatigue stress].any? do |attribute|
      readiness_input.public_send(attribute).present?
    end
    subjective_present ? "mixed" : "healthkit"
  end
end
