# Runs each user's weekly evidence review without waiting to be asked.
#
# The review was reachable only from a button on /weekly_review, so the one rule
# in the DAG that decides whether to change a calorie target ran when somebody
# remembered it — and `NutritionTargetResolver` prefers an adjustment over every
# other way of arriving at a target, so forgetting meant an old correction kept
# setting calories.
#
# Runs hourly like CheckInReminderJob and acts at each user's own local hour, so
# a review lands on the week the user lives in rather than on UTC's.
class ScheduledWeeklyReviewJob < ApplicationJob
  # Early enough that Monday's plan already reflects last week.
  REVIEW_HOUR = 5

  queue_as :default

  def perform
    User.find_each do |user|
      next unless user.local_time.hour == REVIEW_HOUR

      period = review_period(user)
      next if reviewed?(user, period)
      # A review of a week the user did not use would put "keep collecting
      # evidence" on the record every week forever, for an account that recorded
      # nothing to review. Partial evidence still gets one — they are training,
      # and being told what is missing is the point.
      next unless any_evidence?(user, period)

      WeeklyReviewRecomputeJob.perform_later(user)
    end
  end

  private

  # The week that has finished, in the user's own time zone — the same window
  # WeeklyEvidenceReview picks for itself when asked for no particular period.
  def review_period(user)
    period_end = user.local_date.beginning_of_week - 1.day
    (period_end - (WeeklyEvidenceReview::REVIEW_DAYS - 1).days)..period_end
  end

  # Checked every day rather than only on the day the week turns, so a review
  # missed because the worker was down is picked up the next morning instead of
  # skipping the week. The evaluator is idempotent, so a redundant run is free —
  # this only keeps one off the queue.
  def reviewed?(user, period)
    user.coaching_decisions
      .active_evidence
      .of_type("weekly_review")
      .where(rule_key: WeeklyEvidenceReview::RULE_KEY)
      .for_input("period_end", period.last.iso8601)
      .exists?
  end

  def any_evidence?(user, period)
    user.weight_trends.where(trend_date: period).exists? ||
      user.coaching_decisions
        .active_evidence
        .of_type("daily_nutrition")
        .where("(inputs ->> 'nutrition_date')::date BETWEEN ? AND ?", period.first, period.last)
        .exists?
  end
end
