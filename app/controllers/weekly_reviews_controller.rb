class WeeklyReviewsController < ApplicationController
  def show
    today = Current.user.local_date
    @review = Current.user.coaching_decisions
      .where(decision_type: "weekly_review", rule_key: WeeklyEvidenceReview::RULE_KEY)
      .order(created_at: :desc)
      .first
    @adjustment = adjustment_for(@review)
    @active_goal = Current.user.goal_periods
      .where("started_on <= ? AND (ended_on IS NULL OR ended_on >= ?)", today, today)
      .order(started_on: :desc)
      .first
    @current_targets = NutritionTargetResolver.new(
      Current.user,
      goal: @active_goal,
      target_date: today
    ).call
  end

  def create
    WeeklyReviewRecomputeJob.perform_later(Current.user)

    redirect_to weekly_review_path, notice: "Running this week’s evidence review…"
  end

  private

  def adjustment_for(review)
    return unless review

    Current.user.coaching_decisions
      .where(decision_type: "nutrition_adjustment", rule_key: NutritionAdjustmentEvaluator::RULE_KEY)
      .where("inputs ->> 'weekly_review_decision_id' = ?", review.id.to_s)
      .order(created_at: :desc)
      .first
  end
end
