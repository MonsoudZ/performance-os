class TrainingPlanRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  # Recompose today's training plan after a training-side change (a new or ended
  # prescription, a deleted workout). The orchestrator only writes a plan for the
  # current day; older days stay as historical record.
  def perform(user, date)
    DailyTrainingOrchestrator.new(user, plan_date: date).call if date == user.local_date
    broadcast_plan_ready(user)
  end
end
