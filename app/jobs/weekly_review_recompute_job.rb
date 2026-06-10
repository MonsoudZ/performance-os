class WeeklyReviewRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  def perform(user)
    review = WeeklyEvidenceReview.new(user).call
    NutritionAdjustmentEvaluator.new(review).call
    broadcast_plan_ready(user)
  end
end
