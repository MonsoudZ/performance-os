class BodyMetricRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  # Runs for the affected date after a weigh-in is logged or removed, so the
  # weight trend, expenditure, and plan all re-derive from current measurements.
  def perform(user, date)
    WeightTrendMaterializer.new(user, trend_date: date).call
    recompute_daily_plan(user, date)
    broadcast_plan_ready(user)
  end
end
