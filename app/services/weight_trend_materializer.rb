class WeightTrendMaterializer
  ALPHA = 0.25

  def initialize(user, trend_date:)
    @user = user
    @trend_date = trend_date
  end

  def call
    return existing_trend if existing_trend

    raw_kg = daily_weight
    return unless raw_kg

    previous_ewma = user.weight_trends
      .where("trend_date < ?", trend_date)
      .order(trend_date: :desc)
      .pick(:ewma_kg)

    ewma_kg = previous_ewma ? (ALPHA * raw_kg + (1 - ALPHA) * previous_ewma) : raw_kg

    user.weight_trends.create!(
      trend_date: trend_date,
      raw_kg: raw_kg,
      ewma_kg: ewma_kg.round(2)
    )
  end

  private

  attr_reader :user, :trend_date

  def existing_trend
    @existing_trend ||= user.weight_trends.find_by(trend_date: trend_date)
  end

  def daily_weight
    weights = user.body_metrics.where(measured_on: trend_date).where.not(weight_kg: nil).pluck(:weight_kg)
    return if weights.empty?

    weights.sum / weights.size
  end
end
