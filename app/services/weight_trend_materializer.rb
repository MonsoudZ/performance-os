class WeightTrendMaterializer
  ALPHA = 0.25

  def initialize(user, trend_date:)
    @user = user
    @trend_date = trend_date
  end

  def call
    raw_kg = daily_weight

    user.weight_trends.transaction do
      if raw_kg
        upsert_raw(trend_date, raw_kg)
      else
        # The last measurement for this date was removed; drop the trend row so
        # the EWMA chain re-derives without it.
        user.weight_trends.where(trend_date: trend_date).delete_all
      end
      # Recompute this date and every later date so corrections, out-of-order
      # backfills, and deletions propagate through the whole EWMA chain instead
      # of leaving stale downstream rows.
      recompute_ewma_from(trend_date)
    end

    existing_trend
  end

  private

  attr_reader :user, :trend_date

  def existing_trend
    user.weight_trends.find_by(trend_date: trend_date)
  end

  # weight_trends has no primary key (id: false), so rows are written through
  # the (user_id, trend_date) unique key rather than via save!/update!.
  def upsert_raw(date, raw_kg)
    scope = user.weight_trends.where(trend_date: date)
    if scope.exists?
      scope.update_all(raw_kg: raw_kg, updated_at: Time.current)
    else
      user.weight_trends.create!(trend_date: date, raw_kg: raw_kg, ewma_kg: raw_kg)
    end
  end

  def recompute_ewma_from(start_date)
    previous_ewma = user.weight_trends
      .where(trend_date: ...start_date)
      .order(trend_date: :desc)
      .pick(:ewma_kg)

    user.weight_trends
      .where("trend_date >= ?", start_date)
      .order(:trend_date)
      .pluck(:trend_date, :raw_kg)
      .each do |date, raw|
        previous_ewma = previous_ewma ? (ALPHA * raw + (1 - ALPHA) * previous_ewma) : raw
        user.weight_trends.where(trend_date: date).update_all(ewma_kg: previous_ewma.round(2), updated_at: Time.current)
      end
  end

  def daily_weight
    weights = user.body_metrics.where(measured_on: trend_date).where.not(weight_kg: nil).pluck(:weight_kg)
    return if weights.empty?

    weights.sum / weights.size
  end
end
