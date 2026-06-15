class WeeklyReviewsController < ApplicationController
  def show
    today = Current.user.local_date
    @review = Current.user.coaching_decisions
      .active_evidence
      .of_type("weekly_review")
      .where(rule_key: WeeklyEvidenceReview::RULE_KEY)
      .latest_first
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
      .active_evidence
      .of_type("nutrition_adjustment")
      .where(rule_key: NutritionAdjustmentEvaluator::RULE_KEY)
      .for_input("weekly_review_decision_id", review.id)
      .latest_first
      .first
  end
end
