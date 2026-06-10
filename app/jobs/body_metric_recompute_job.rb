class BodyMetricRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  def perform(body_metric)
    user = body_metric.user
    date = body_metric.measured_on
    WeightTrendMaterializer.new(user, trend_date: date).call
    recompute_daily_plan(user, date)
    broadcast_plan_ready(user)
  end
end
