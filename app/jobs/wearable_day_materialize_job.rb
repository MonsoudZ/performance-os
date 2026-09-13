class WearableDayMaterializeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  # Build everything a day of synced samples implies, then re-run the evaluator
  # pipeline once over the result. Deferred from the sync request so the device's
  # API call returns immediately (202 Accepted) instead of blocking on it.
  def perform(user, metric_date)
    WearableDayMaterializer.new(user, metric_date: metric_date).call
    recompute_daily_plan(user, metric_date)
    broadcast_plan_ready(user) if metric_date == user.local_date
  end
end
