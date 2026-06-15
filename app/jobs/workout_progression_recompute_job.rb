class WorkoutProgressionRecomputeJob < ApplicationJob
  include DailyPlanRecompute

  queue_as :default

  def perform(workout_session)
    user = workout_session.user
    DoubleProgressionEvaluator.new(workout_session).call
    # Editing any workout can retract today's plan — its progression decision may
    # be the latest evidence the current day's plan is built on, even when the
    # workout itself is from a past day. Always recompose today's plan so a
    # retraction can't leave the dashboard without one. The orchestrator is
    # idempotent and returns the existing plan when nothing changed.
    DailyTrainingOrchestrator.new(user).call
    broadcast_plan_ready(user)
  end
end
