# Two ways to arrive at the same number, in order of how much they are worth.
#
# Energy balance is measured outcome: what the user ate against what their weight
# actually did, so it prices in everything a device cannot see. It needs a week
# of both before it says anything, which is a week a newly paired user spends
# with no calorie target at all.
#
# A wearable's own basal + active figures fill exactly that gap. They are a model
# rather than a measurement — the device is guessing from heart rate and motion —
# so they are never preferred over energy balance and never rise above low
# confidence. Which of the two produced a row is recorded on it.
class ExpenditureEstimator
  MINIMUM_INTAKE_DAYS = 7
  MINIMUM_TREND_SPAN_DAYS = 7
  KCAL_PER_KG = 7_700

  # Days of device energy averaged into one estimate. A single day swings with
  # one long walk; a week of them is a habit.
  WEARABLE_WINDOW_DAYS = 7
  WEARABLE_ENERGY_METRICS = %w[active_energy_kcal basal_energy_kcal].freeze

  def initialize(user, estimate_date: nil)
    @user = user
    @estimate_date = estimate_date || user.local_date
  end

  def call
    return energy_balance_estimate if evidence_sufficient?

    wearable_energy_estimate
  end

  private

  attr_reader :user, :estimate_date

  def energy_balance_estimate
    average_intake = daily_intakes.sum / daily_intakes.size.to_f
    weight_change_per_day = (latest_trend.ewma_kg - earliest_trend.ewma_kg) / trend_span_days

    persist(
      basis: "energy_balance",
      intake_kcal: average_intake.round(1),
      trend_weight_kg: latest_trend.ewma_kg,
      estimated_tdee: (average_intake - (weight_change_per_day * KCAL_PER_KG)).round(1),
      confidence: confidence
    )
  end

  def wearable_energy_estimate
    daily_totals = wearable_daily_energy
    return if daily_totals.empty?

    average = daily_totals.sum / daily_totals.size
    return unless average.positive?

    persist(
      basis: "wearable_energy",
      intake_kcal: nil,
      trend_weight_kg: latest_trend&.ewma_kg,
      estimated_tdee: average.round(1),
      confidence: "low"
    )
  end

  # expenditure_estimates has no primary key (id: false), so a persisted row
  # cannot be written back through save! — Rails builds the UPDATE around the
  # primary key and there isn't one. Rows are reached through the
  # (user_id, estimate_date) unique index instead, the same way weight_trends
  # are, and validated first because update_all does not.
  def persist(attributes)
    attributes = attributes.merge(computed_at: Time.current)
    scope = user.expenditure_estimates.where(estimate_date: estimate_date)
    existing = scope.take
    return user.expenditure_estimates.create!(attributes.merge(estimate_date: estimate_date)) if existing.nil?

    existing.assign_attributes(attributes)
    existing.validate!
    scope.update_all(attributes)
    existing
  end

  # Total device-reported energy for each complete day in the window that
  # reported both halves of it. A day with active energy but no basal is not a
  # smaller day — it is a day the device only told us half about, and averaging
  # it in would understate expenditure by roughly a basal rate.
  def wearable_daily_energy
    user.wearable_samples
      .where(metric_type: WEARABLE_ENERGY_METRICS)
      .where(started_at: user.local_day_range(wearable_window.begin).begin..user.local_day_range(wearable_window.end).end)
      .where.not(value: nil)
      .pluck(:metric_type, :started_at, :value)
      .group_by { |_metric_type, started_at, _value| user.local_date_at(started_at) }
      .values
      .filter_map do |rows|
        reported = rows.map(&:first).uniq
        next unless WEARABLE_ENERGY_METRICS.all? { |metric| reported.include?(metric) }

        rows.sum { |_metric_type, _started_at, value| Units.decimal(value) }
      end
  end

  # Complete days only. A day still being lived has only the energy burned so
  # far, and a TDEE read off it at breakfast would set the day's calorie target
  # at a few hundred kilocalories.
  def wearable_window
    last_complete_day = [ estimate_date, user.local_date - 1 ].min
    first_day = last_complete_day - (WEARABLE_WINDOW_DAYS - 1)
    first_day..last_complete_day
  end

  # Intake and the weight delta must describe the SAME period; otherwise the
  # energy-balance identity (TDEE = average intake - stored energy) does not
  # hold. We anchor the intake window to the span actually covered by weight
  # trends, using the user's local day boundaries rather than the server zone.
  def daily_intakes
    @daily_intakes ||= user.food_log_entries
      .where(logged_at: intake_window)
      .order(:logged_at)
      .to_a
      .group_by { |entry| user.local_date_at(entry.logged_at) }
      .values
      .map { |entries| entries.sum(&:kcal) }
  end

  def intake_window
    user.local_day_range(earliest_trend.trend_date).begin..user.local_day_range(latest_trend.trend_date).end
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

  # Order matters: daily_intakes derives its window from the trend span, so the
  # trend checks must short-circuit before daily_intakes is evaluated.
  def evidence_sufficient?
    trends.size >= 2 &&
      trend_span_days >= MINIMUM_TREND_SPAN_DAYS &&
      daily_intakes.size >= MINIMUM_INTAKE_DAYS
  end

  def confidence
    return "high" if daily_intakes.size >= 21 && trend_span_days >= 21
    return "moderate" if daily_intakes.size >= 14 && trend_span_days >= 14

    "low"
  end
end
