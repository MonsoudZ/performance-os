class NutritionRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  def perform(user, date)
    recompute_daily_plan(user, date)
    broadcast_plan_ready(user)
  end
end
