class ReadinessRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  def perform(readiness_input)
    user = readiness_input.user
    ReadinessEvaluator.new(readiness_input).call
    NutritionEvaluator.new(user).call
    DailyTrainingOrchestrator.new(user).call
    broadcast_plan_ready(user)
  end
end
