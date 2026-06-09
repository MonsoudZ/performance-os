class ExpenditureEstimator
  MINIMUM_INTAKE_DAYS = 7
  MINIMUM_TREND_SPAN_DAYS = 7
  KCAL_PER_KG = 7_700

  def initialize(user, estimate_date: nil)
    @user = user
    @estimate_date = estimate_date || user.local_date
  end

  def call
    return unless evidence_sufficient?

    average_intake = daily_intakes.sum / daily_intakes.size
    weight_change_per_day = (latest_trend.ewma_kg - earliest_trend.ewma_kg) / trend_span_days
    estimated_tdee = average_intake - (weight_change_per_day * KCAL_PER_KG)

    user.expenditure_estimates.find_or_initialize_by(estimate_date: estimate_date).tap do |estimate|
      estimate.assign_attributes(
        intake_kcal: average_intake.round(1),
        trend_weight_kg: latest_trend.ewma_kg,
        estimated_tdee: estimated_tdee.round(1),
        confidence: confidence,
        computed_at: Time.current
      )
      estimate.save!
    end
  end

  private

  attr_reader :user, :estimate_date

  def daily_intakes
    @daily_intakes ||= user.food_log_entries
      .where(logged_at: evidence_start.beginning_of_day..estimate_date.end_of_day)
      .order(:logged_at)
      .to_a
      .group_by { |entry| user.local_date_at(entry.logged_at) }
      .values
      .map { |entries| entries.sum(&:kcal) }
  end

  def trends
    @trends ||= user.weight_trends
      .where(trend_date: evidence_start..estimate_date)
      .order(:trend_date)
      .to_a
  end

  def earliest_trend
    trends.first
  end

  def latest_trend
    trends.last
  end

  def trend_span_days
    (latest_trend.trend_date - earliest_trend.trend_date).to_i
  end

  def evidence_start
    estimate_date - 27.days
  end

  def evidence_sufficient?
    daily_intakes.size >= MINIMUM_INTAKE_DAYS &&
      trends.size >= 2 &&
      trend_span_days >= MINIMUM_TREND_SPAN_DAYS
  end

  def confidence
    return "high" if daily_intakes.size >= 21 && trend_span_days >= 21
    return "moderate" if daily_intakes.size >= 14 && trend_span_days >= 14

    "low"
  end
end
