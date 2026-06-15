class WearableReadinessMaterializeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  # Build the day's readiness input from synced wearable samples and run the
  # evaluator pipeline. Deferred from the sync request so the device's API call
  # returns immediately (202 Accepted) instead of blocking on the evaluators.
  def perform(user, metric_date)
    WearableReadinessMaterializer.new(user, metric_date: metric_date).call
    broadcast_plan_ready(user) if metric_date == user.local_date
  end
end
