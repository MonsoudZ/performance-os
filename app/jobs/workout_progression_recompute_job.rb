class WorkoutProgressionRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  def perform(workout_session)
    user = workout_session.user
    DoubleProgressionEvaluator.new(workout_session).call
    if user.local_date_at(workout_session.performed_at) == user.local_date
      DailyTrainingOrchestrator.new(user).call
    end
    broadcast_plan_ready(user)
  end
end
