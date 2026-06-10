module DailyPlanRecompute
  private

  # Shared evaluator pipeline for a single day. Each evaluator is idempotent and
  # short-circuits when its inputs are unchanged, so re-running is safe.
  def recompute_daily_plan(user, date)
    ExpenditureEstimator.new(user, estimate_date: date).call
    NutritionEvaluator.new(user, nutrition_date: date).call
    DailyTrainingOrchestrator.new(user, plan_date: date).call if date == user.local_date
  end

  # Tell every page the user has open on this stream to morph-refresh itself so
  # the freshly computed decision replaces the "Calculating…" placeholder.
  def broadcast_plan_ready(user)
    Turbo::StreamsChannel.broadcast_refresh_to(user)
  end
end
