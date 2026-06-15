module TrainingRecomputable
  extend ActiveSupport::Concern

  private

  # Recompose the day's training plan after a change that feeds it: a new or
  # ended prescription, a logged conditioning session, a started/ended block,
  # or a deleted workout. Defaults to today; the orchestrator only writes a
  # plan for the current day.
  def recompute_training_plan(date = Current.user.local_date)
    TrainingPlanRecomputeJob.perform_later(Current.user, date)
  end
end
